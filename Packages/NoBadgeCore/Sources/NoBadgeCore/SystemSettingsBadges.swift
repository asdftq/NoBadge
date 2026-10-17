import CoreFoundation
import Darwin
import Foundation

/// System Settings draws its own Dock badge. Keep its adapter separate from
/// usernoted permissions, and durably retain only the counters we actually hide.
public actor SystemSettingsBadges {
    public static let bundleID = "com.apple.systempreferences"
    private struct Session: Codable {
        var schema = 2
        var owner = getuid()
        var home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        var adapter = "system-settings-attention-v1"
        var source: String?
        var originals: [String: Int] = [:]
    }
    private struct Envelope: Codable { let payload: Data; let checksum: String }
    private let journal: URL
    private let domain: String
    private let preferenceFile: URL
    private var preferenceDomain: String { preferenceFile.deletingPathExtension().path }
    private let canSuppress: Bool
    private let notify: @Sendable () -> Void
    private let key = "AttentionPrefBundleIDs"

    public init(journal: URL, canSuppress: Bool, domain: String = "com.apple.systempreferences",
                preferenceFile: URL? = nil,
                notify: @escaping @Sendable () -> Void = {
                    DistributedNotificationCenter.default().postNotificationName(
                        Notification.Name("com.apple.systempreferences.refreshdocktile"),
                        object: nil, userInfo: nil, deliverImmediately: true)
                }) {
        self.journal = journal; self.canSuppress = canSuppress
        self.domain = domain; self.notify = notify
        self.preferenceFile = (preferenceFile ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(domain).plist")).standardizedFileURL
    }

    public func pendingRecovery() -> Bool { FileManager.default.fileExists(atPath: journal.path) }
    public func signature() throws -> String {
        try counts().sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "|")
    }
    private func counts(source: String? = nil) throws -> [String: Int] {
        // A bare bundle identifier makes defaults resolve the app's sandbox
        // container. The Dock plug-in reads the user's NON-container domain.
        // Pin the source explicitly: a successful write to the other domain
        // cannot establish that the Dock's counter changed.
        let source = source ?? preferenceDomain
        if source == preferenceDomain, FileManager.default.fileExists(atPath: preferenceFile.path) {
            let attrs = try FileManager.default.attributesOfItem(atPath: preferenceFile.path)
            let values = try preferenceFile.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                  values.isSymbolicLink != true, values.isRegularFile == true
            else { throw EngineError.invalidSchema }
        }
        let result = try defaults(["export", source, "-"])
        if result.status != 0 {
            if source == preferenceDomain, !FileManager.default.fileExists(atPath: preferenceFile.path),
               !pendingRecovery() { return [:] }
            throw EngineError.unavailable("Cannot read system badge settings.")
        }
        guard let root = try PropertyListSerialization.propertyList(from: result.data, format: nil) as? [String: Any]
        else { throw EngineError.invalidSchema }
        let value = root[key]
        guard let value else { return [:] }
        guard let raw = value as? [String: NSNumber], raw.allSatisfy({ id, n in
            !id.isEmpty && CFGetTypeID(n) != CFBooleanGetTypeID() &&
            !["f", "d"].contains(String(cString: n.objCType)) && n.int64Value >= 0 && n.int64Value <= Int.max
        }) else { throw EngineError.invalidSchema }
        return raw.mapValues(\.intValue)
    }
    /// No await inside a transaction: actor reentrancy cannot interleave a restore.
    public func reconcile(hidden: Bool, excepted: Bool) throws -> Int {
        guard hidden && !excepted && canSuppress else { try restore(); return 0 }
        // 0.1.40 journals belong to its implicit defaults source. Recover that
        // exact old path before taking a new baseline from the Dock's source.
        if try load()?.schema == 1 { try restore() }
        let before = try counts()
        var session = try load() ?? Session(source: preferenceDomain)
        // A removed source must never be resurrected during restoration.
        session.originals = session.originals.filter { before[$0.key] != nil }
        // A freshly regenerated count supersedes the previously captured count.
        for (id, count) in before where count > 0 { session.originals[id] = count }
        guard !session.originals.isEmpty else { try clear(); return 0 }
        let desired = before.mapValues { _ in 0 }
        try save(session)
        if desired != before { try write(desired, expected: before) }
        return 1
    }
    public func restore() throws {
        guard let session = try load() else { return }
        let source = session.schema == 1 ? domain : preferenceDomain
        let before = try counts(source: source)
        var desired = before
        // Preserve removed entries and newer external counts rather than copying
        // an old dictionary over current system attention state.
        for (id, original) in session.originals where before[id] == 0 { desired[id] = original }
        if desired != before { try write(desired, expected: before, source: source) }
        try clear()
    }
    private func write(_ desired: [String: Int], expected: [String: Int], source: String? = nil) throws {
        let source = source ?? preferenceDomain
        guard try counts(source: source) == expected else { throw EngineError.concurrentModification }
        let arguments = ["write", source, key, "-dict"] + desired.sorted { $0.key < $1.key }
            .flatMap { [$0.key, "-int", String($0.value)] }
        guard try defaults(arguments).status == 0, try counts(source: source) == desired else {
            throw EngineError.verificationFailed
        }
        notify()
    }
    private func defaults(_ arguments: [String]) throws -> (status: Int32, data: Data) {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("nobadge-defaults-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: output.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else { throw EngineError.invalidJournal }
        defer { try? FileManager.default.removeItem(at: output) }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = arguments
        process.standardOutput = handle; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while process.isRunning && ContinuousClock.now < deadline { usleep(10_000) }
        if process.isRunning {
            process.terminate()
            let grace = ContinuousClock.now.advanced(by: .milliseconds(200))
            while process.isRunning && ContinuousClock.now < grace { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw EngineError.unavailable("System badge settings timed out.")
        }
        process.waitUntilExit()
        guard try handle.offset() <= 1_048_576 else { throw EngineError.invalidSchema }
        return (process.terminationStatus, try Data(contentsOf: output))
    }
    private func load() throws -> Session? {
        guard pendingRecovery() else { return nil }
        let attrs = try FileManager.default.attributesOfItem(atPath: journal.path)
        guard (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              try journal.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true
        else { throw EngineError.invalidJournal }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: journal))
            guard NotificationSnapshot.hash(envelope.payload) == envelope.checksum else { throw EngineError.invalidJournal }
            let session = try JSONDecoder().decode(Session.self, from: envelope.payload)
            guard (session.schema == 1 && session.source == nil ||
                   session.schema == 2 && session.source == preferenceDomain), session.owner == getuid(),
                  session.home == FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path,
                  session.adapter == "system-settings-attention-v1",
                  session.originals.allSatisfy({ !$0.key.isEmpty && $0.value > 0 })
            else { throw EngineError.invalidJournal }
            return session
        } catch { throw EngineError.invalidJournal }
    }
    private func save(_ session: Session) throws {
        let parent = journal.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        guard try parent.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw EngineError.invalidJournal
        }
        let payload = try JSONEncoder().encode(session)
        let data = try JSONEncoder().encode(Envelope(payload: payload, checksum: NotificationSnapshot.hash(payload)))
        let temporary = parent.appendingPathComponent(".system-badge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil,
                                             attributes: [.posixPermissions: 0o600]) else { throw EngineError.invalidJournal }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try handle.write(contentsOf: data); try handle.synchronize()
        guard rename(temporary.path, journal.path) == 0 else { throw POSIXError(.EIO) }
        syncDirectory()
    }
    private func clear() throws {
        if pendingRecovery() { try FileManager.default.removeItem(at: journal); syncDirectory() }
    }
    private func syncDirectory() {
        let fd = open(journal.deletingLastPathComponent().path, O_RDONLY)
        if fd >= 0 { _ = fsync(fd); close(fd) }
    }
}
