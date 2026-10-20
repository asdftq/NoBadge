import Foundation
import Darwin

public struct JournalEntry: Codable, Equatable, Sendable {
    public let bundleID: String
    public let originalBadgeEnabled: Bool
    public var owned = true
    public var verified = false
    public var absent = false
    public var releaseReason: String?
    public init(bundleID: String, originalBadgeEnabled: Bool) { self.bundleID = bundleID; self.originalBadgeEnabled = originalBadgeEnabled }
}
public struct RecoveryJournal: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let sessionID: UUID
    public let ownerUID: UInt32
    public let canonicalHome: String
    public let adapterID: String
    public let osBuild: String
    public let appVersion: String
    public var phase: String
    public let createdAt: Date
    public var updatedAt: Date
    public var transactionSequence: Int
    public var preWriteFingerprint: String?
    public var intendedPostFingerprint: String?
    public var entries: [String: JournalEntry]
    public var lastVerifiedAt: Date?
    public init(version: String, osBuild: String) {
        schemaVersion = 1; sessionID = UUID(); ownerUID = getuid()
        canonicalHome = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        adapterID = "usernoted-badge-v1"; self.osBuild = osBuild; appVersion = version
        phase = "prepared"; createdAt = .now; updatedAt = .now; transactionSequence = 0; entries = [:]
    }
    public var ownedIDs: Set<String> { Set(entries.values.filter { $0.owned && !$0.absent }.map(\.bundleID)) }
    public func validateIdentity() throws {
        guard schemaVersion == 1, ownerUID == getuid(),
              canonicalHome == FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path,
              adapterID == "usernoted-badge-v1", ["prepared","applied","restoring","needsRecovery"].contains(phase),
              entries.allSatisfy({ $0.key == $0.value.bundleID }) else { throw EngineError.invalidJournal }
    }
}
public protocol JournalPersistence: Sendable {
    func load() async throws -> RecoveryJournal?
    func save(_ journal: RecoveryJournal) async throws
    func clear() async throws
    func finishRestoration() async throws
    func unfinishedRestorationReceipt() async throws -> RecoveryJournal?
    func finishReceiptRefresh(_ journal: RecoveryJournal) async throws
}
public extension JournalPersistence {
    func finishRestoration() async throws { try await clear() }
    func unfinishedRestorationReceipt() async throws -> RecoveryJournal? { nil }
    func finishReceiptRefresh(_ journal: RecoveryJournal) async throws {}
}
public actor FileJournalStore: JournalPersistence {
    private struct Envelope: Codable { let payload: Data; let checksum: String }
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> RecoveryJournal? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath:url.path)
        guard (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
              (try url.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else { throw EngineError.invalidJournal }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self,from:Data(contentsOf:url))
            guard NotificationSnapshot.hash(envelope.payload) == envelope.checksum else { throw EngineError.invalidJournal }
            let journal = try JSONDecoder().decode(RecoveryJournal.self,from:envelope.payload)
            try journal.validateIdentity(); return journal
        } catch { throw EngineError.invalidJournal }
    }
    public func save(_ journal: RecoveryJournal) throws {
        try journal.validateIdentity()
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        guard (try folder.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true else { throw EngineError.invalidJournal }
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:folder.path)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        let payload=try encoder.encode(journal);let data=try encoder.encode(Envelope(payload:payload,checksum:NotificationSnapshot.hash(payload)))
        let temporary=folder.appendingPathComponent(".journal-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at:temporary) }
        guard FileManager.default.createFile(atPath:temporary.path,contents:nil,attributes:[.posixPermissions:0o600]) else { throw EngineError.invalidJournal }
        let handle=try FileHandle(forWritingTo:temporary);try handle.write(contentsOf:data);try handle.synchronize();try handle.close()
        guard rename(temporary.path,url.path)==0 else { throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO) }
        syncDirectory(folder)
    }
    public func clear() throws {
        guard FileManager.default.fileExists(atPath:url.path) else { return }
        try FileManager.default.removeItem(at:url);syncDirectory(url.deletingLastPathComponent())
    }
    /// Keep the last originals after immediate verification. A later OS cache
    /// write must not destroy our only record of what the customer had enabled.
    /// This receipt is never applied automatically over subsequent user edits.
    public func finishRestoration() async throws {
        guard try load() != nil else { return }
        let folder = url.deletingLastPathComponent()
        let receipt = folder.appendingPathComponent("last-restored-session.json")
        guard rename(url.path, receipt.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        syncDirectory(folder)
    }
    public func unfinishedRestorationReceipt() async throws -> RecoveryJournal? {
        let receipt = FileJournalStore(url: url.deletingLastPathComponent().appendingPathComponent("last-restored-session.json"))
        guard let session = try await receipt.load(),
              session.phase == "needsRecovery" || session.phase == "restoring" else { return nil }
        return session
    }
    public func finishReceiptRefresh(_ journal: RecoveryJournal) async throws {
        let receipt = FileJournalStore(url: url.deletingLastPathComponent().appendingPathComponent("last-restored-session.json"))
        try await receipt.save(journal)
    }
    private func syncDirectory(_ folder: URL) { let fd=open(folder.path,O_RDONLY);if fd>=0 {_=fsync(fd);close(fd)} }
}
