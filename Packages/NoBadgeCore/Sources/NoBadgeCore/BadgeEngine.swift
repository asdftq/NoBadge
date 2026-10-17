import Foundation

public struct EngineResult: Equatable, Sendable {
    public let hiddenCount: Int
    public let wrote: Bool
    public let hasSession: Bool
}

/// Serializes across awaits as well as actor isolation; an actor alone is reentrant.
public actor BadgeEngine {
    private let store: any NotificationStore
    private let journals: any JournalPersistence
    private let refresher: any DaemonRefreshing
    private let version: String
    private let osBuild: String
    private let verificationDelay: Duration
    private let refreshInterval: TimeInterval
    private let recoveryBuilds: Set<String>
    private var lastRefresh: ContinuousClock.Instant?
    private var locked=false
    private var waiters: [CheckedContinuation<Void,Never>] = []
    private var failures: [ContinuousClock.Instant] = []
    private var restoreRequested=false
    private var intentRevision: UInt64 = 0
    public init(store: any NotificationStore, journals: any JournalPersistence, refresher: any DaemonRefreshing, version: String, osBuild: String, verificationDelay: Duration = .milliseconds(500), refreshInterval: TimeInterval = 10, compatibleRecoveryBuilds: Set<String>? = nil) {
        self.store=store;self.journals=journals;self.refresher=refresher;self.version=version;self.osBuild=osBuild;self.verificationDelay=verificationDelay;self.refreshInterval=refreshInterval;self.recoveryBuilds=compatibleRecoveryBuilds ?? [osBuild]
    }
    private func acquire() async { if !locked { locked=true;return };await withCheckedContinuation { waiters.append($0) } }
    private func release() { if waiters.isEmpty {locked=false} else {waiters.removeFirst().resume()} }
    /// Stops queued suppression cooldowns while the application drains active work.
    public func prioritizeRestoration() { restoreRequested=true }
    /// Invalidates only work that has not committed; the next refresh uses fresh policy.
    public func invalidatePendingSuppression() { intentRevision &+= 1 }
    public func resetFailureBreaker() { failures=[] }
    public func pendingRecovery() async throws -> Bool { try await journals.load() != nil }

    public func reconcile(hidden: Bool, exceptions: Set<String> = [], eligibleIDs: Set<String>? = nil, qualified: Bool) async throws -> EngineResult {
        let revision = intentRevision
        if !hidden {restoreRequested=true}
        await acquire();defer {release()}
        if !hidden {defer {restoreRequested=false};return try await restoreLocked()}
        guard qualified else { throw EngineError.unsupportedOS }
        failures=failures.filter {$0.duration(to: .now) < .seconds(60)}
        guard failures.count<3 else {throw EngineError.verificationFailed}
        var conflicts = 0
        while true {
        if restoreRequested || revision != intentRevision {
            let pending = try await journals.load()
            return .init(hiddenCount: pending?.ownedIDs.count ?? 0, wrote: false, hasSession: pending != nil)
        }
        var session=try await journals.load() ?? RecoveryJournal(version:version,osBuild:osBuild)
        // A previous incomplete transaction must be recovered, not enrolled again.
        guard session.phase == "applied" || session.entries.isEmpty else { throw EngineError.verificationFailed }
        let originalSession=session
        let snapshot=try await store.read()
        var bits:[String:Bool]=[:]
        var journalChanged=false
        var releaseAfterCommit: Set<String> = []
        for (id,entry) in session.entries where entry.owned {
            guard let record=snapshot.records.first(where:{$0.id==id}) else {session.entries[id]?.absent=true;session.entries[id]?.owned=false;session.entries[id]?.releaseReason="external";journalChanged=true;continue}
            if entry.verified && record.badgeEnabled {session.entries[id]?.owned=false;session.entries[id]?.releaseReason="external";journalChanged=true;continue}
            if exceptions.contains(id) || eligibleIDs.map({!$0.contains(id)}) == true {
                if record.badgeEnabled != entry.originalBadgeEnabled {bits[id]=entry.originalBadgeEnabled;releaseAfterCommit.insert(id)}
                else {session.entries[id]?.owned=false;session.entries[id]?.releaseReason="exception"}
                journalChanged=true
            }
        }
        for record in snapshot.records where !exceptions.contains(record.id) && (eligibleIDs?.contains(record.id) ?? true) {
            if session.entries[record.id]?.releaseReason == "exception" {session.entries[record.id]=nil}
            guard session.entries[record.id] == nil, record.badgeEnabled else {continue}
            session.entries[record.id]=JournalEntry(bundleID:record.id,originalBadgeEnabled:record.badgeEnabled)
            bits[record.id]=false;journalChanged=true
        }
        if bits.isEmpty {
            if journalChanged {session.updatedAt = .now;try await journals.save(session)}
            return .init(hiddenCount:session.ownedIDs.count,wrote:false,hasSession:!session.entries.isEmpty)
        }
        // No-op refreshes must never wait or disable the UI. Rate-limit actual
        // suppression writes only, then re-read to avoid committing a stale snapshot.
        if bits.values.contains(false), let lastRefresh, lastRefresh.duration(to: .now) < .seconds(refreshInterval) {
            while lastRefresh.duration(to: .now) < .seconds(refreshInterval) && !restoreRequested && revision == intentRevision {
                try await Task.sleep(for: .milliseconds(50))
            }
            if restoreRequested || revision != intentRevision {
                let pending = try await journals.load()
                return .init(hiddenCount: pending?.ownedIDs.count ?? 0, wrote: false, hasSession: pending != nil)
            }
            continue
        }
        do {
            try await commit(bits:bits,snapshot:snapshot,session:&session,restoring:false)
            if !releaseAfterCommit.isEmpty {
                for id in releaseAfterCommit {session.entries[id]?.owned=false;session.entries[id]?.releaseReason="exception"}
                try await journals.save(session)
            }
        } catch EngineError.concurrentModification {
            // The store's concurrency error means its write did not occur.
            if originalSession.entries.isEmpty {try await journals.clear()} else {try await journals.save(originalSession)}
            // Registration/cache updates are common around a daemon refresh.
            // Recompute from a fresh snapshot; never retry the old patched data.
            // Persistent contention still stops safely after three attempts.
            conflicts += 1
            guard conflicts < 3 else {throw EngineError.concurrentModification}
            try await Task.sleep(for: .milliseconds(100 * conflicts), clock: .continuous)
            continue
        } catch {
            failures.append(.now);throw error
        }
        return .init(hiddenCount:session.ownedIDs.count,wrote:true,hasSession:true)
        }
    }
    public func restore() async throws -> EngineResult {restoreRequested=true;await acquire();defer {restoreRequested=false;release()};return try await restoreLocked()}
    private func restoreLocked() async throws -> EngineResult {
        // usernoted can update registration metadata immediately after suppression.
        // A conflict means no write happened. Re-read and recompute restoration,
        // preserving fresh unrelated settings, instead of abandoning a normal quit.
        for attempt in 0..<3 {
            do { return try await restoreAttempt() }
            catch EngineError.concurrentModification {
                if attempt == 2 { throw EngineError.concurrentModification }
                try await Task.sleep(for: .milliseconds(100 * (attempt + 1)))
            }
        }
        throw EngineError.concurrentModification
    }
    private func restoreAttempt() async throws -> EngineResult {
        guard var session=try await journals.load() else {return .init(hiddenCount:0,wrote:false,hasSession:false)}
        try session.validateIdentity()
        guard recoveryBuilds.contains(osBuild), recoveryBuilds.contains(session.osBuild) else { throw EngineError.unsupportedOS }
        if session.ownedIDs.isEmpty {try await journals.clear();return .init(hiddenCount:0,wrote:false,hasSession:false)}
        let snapshot=try await store.read();var bits:[String:Bool]=[:]
        for id in session.ownedIDs {
            guard let record=snapshot.records.first(where:{$0.id==id}) else {session.entries[id]?.absent=true;session.entries[id]?.owned=false;continue}
            let wanted=session.entries[id]!.originalBadgeEnabled
            if record.badgeEnabled != wanted {bits[id]=wanted}
        }
        if !bits.isEmpty {try await commit(bits:bits,snapshot:snapshot,session:&session,restoring:true)}
        try await journals.finishRestoration()
        return .init(hiddenCount:0,wrote:!bits.isEmpty,hasSession:false)
    }
    private func commit(bits: [String:Bool], snapshot: NotificationSnapshot, session: inout RecoveryJournal, restoring: Bool) async throws {
        session.phase=restoring ? "restoring" : "prepared";session.updatedAt = .now;session.transactionSequence += 1
        let data=try snapshot.patched(bits)
        session.preWriteFingerprint=snapshot.fingerprint;session.intendedPostFingerprint=NotificationSnapshot.hash(data)
        try await journals.save(session)
        try await store.write(data:data,expectedFingerprint:snapshot.fingerprint)
        do {
            try await refresher.refresh();lastRefresh = .now
            try await verify(bits:bits,original:snapshot)
            if verificationDelay > .zero {try await Task.sleep(for:verificationDelay)}
            try await verify(bits:bits,original:snapshot)
            for id in bits.keys {session.entries[id]?.verified=true}
            session.phase="applied";session.lastVerifiedAt = .now;session.updatedAt = .now
            try await journals.save(session)
        } catch {
            session.phase="needsRecovery";session.updatedAt = .now
            // Preserve the prior prepared journal even when saving the error phase fails.
            try? await journals.save(session);throw error
        }
    }
    private func verify(bits:[String:Bool], original:NotificationSnapshot) async throws {
        let current=try await store.read()
        guard bits.allSatisfy({id,bit in current.records.first(where:{$0.id==id})?.badgeEnabled == bit}),
              original.preferencesEqual(current,excludingBadgeBitsFor:Set(bits.keys)) else {throw EngineError.verificationFailed}
    }
}
