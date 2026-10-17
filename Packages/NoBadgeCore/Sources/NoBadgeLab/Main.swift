import Foundation
import NoBadgeCore
import Intents

@main struct LabMain {
    static func main() async {
        do { try await run() } catch { print("labFailure=\(String(describing:error)); recovery data retained"); exit(1) }
    }
    static func run() async throws {
        let args = CommandLine.arguments
        if let command = args.dropFirst().first,
           ["seed-test-journal", "verify-full-test-journal"].contains(command) {
            guard args.count == 3, args[2].hasPrefix("/Volumes/NoBadge-QA-Full/NoBadge-Journal-QA/") else {
                throw EngineError.unavailable("Storage probes are restricted to the isolated NoBadge-QA-Full volume.")
            }
            let url = URL(fileURLWithPath: args[2])
            let journal = FileJournalStore(url: url)
            if command == "seed-test-journal" {
                guard !FileManager.default.fileExists(atPath: url.path) else { throw EngineError.invalidJournal }
                var baseline = RecoveryJournal(version: "storage-QA", osBuild: "synthetic")
                baseline.entries["synthetic.fixture"] = JournalEntry(bundleID: "synthetic.fixture", originalBadgeEnabled: true)
                try await journal.save(baseline)
                print("{\"seeded\":true}")
            } else {
                guard var changed = try await journal.load() else { throw EngineError.invalidJournal }
                let original = changed
                changed.transactionSequence += 1
                var rejected = false
                do { try await journal.save(changed) } catch { rejected = true }
                guard rejected, try await journal.load() == original else { throw EngineError.verificationFailed }
                let freshURL = url.deletingLastPathComponent().appendingPathComponent("fresh.json")
                let fresh = FileJournalStore(url: freshURL)
                var freshRejected = false
                do { try await fresh.save(changed) } catch { freshRejected = true }
                guard freshRejected, !FileManager.default.fileExists(atPath: freshURL.path) else { throw EngineError.verificationFailed }
                print("{\"fullDiskWriteRejected\":true,\"previousDurableJournalPreserved\":true,\"newJournalRejected\":true,\"notificationStoreTouched\":false}")
            }
            return
        }
        let store = FileNotificationStore(url: FileNotificationStore.currentURL)
        let snapshot = try await store.read()
        let testIDs: Set<String> = ["com.asdftq.nobadge.fixture.a", "com.asdftq.nobadge.fixture.b"]
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NoBadgeLab")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
        let journalURL = folder.appendingPathComponent("recovery.json")
        if args.contains("reset-fixtures") {
            guard !FileManager.default.fileExists(atPath: journalURL.path) else { throw EngineError.invalidJournal }
            let baselineURL=URL(fileURLWithPath:"/tmp/nobadge-live-verification/baseline.plist")
            let baseline=try NotificationSnapshot(data:Data(contentsOf:baselineURL))
            let bits=Dictionary(uniqueKeysWithValues:baseline.records.filter{testIDs.contains($0.id)}.map{($0.id,$0.badgeEnabled)})
            guard bits.count==2 else {throw EngineError.invalidSchema}
            try await store.write(data:snapshot.patched(bits),expectedFingerprint:snapshot.fingerprint)
            try await UserNotificationRefresher().refresh()
            print("Synthetic fixture baseline restored through preferences service; unrelated app records unchanged.")
            return
        }
        if args.contains("probe") {
            let db = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
            let focus = FocusDecoder.decode(assertions:try Data(contentsOf:db.appendingPathComponent("Assertions.json")),configurations:try Data(contentsOf:db.appendingPathComponent("ModeConfigurations.json")))
            let publicStatus = await MainActor.run { String(describing: INFocusStatusCenter.default.focusStatus.isFocused) }
            print("OS=\(ProcessInfo.processInfo.operatingSystemVersionString), focusKnown=\(focus.activeIDs != nil), activeCount=\(focus.activeIDs?.count ?? -1), publicStatus=\(publicStatus)")
            for r in snapshot.records where testIDs.contains(r.id) { print("\(r.id) flags=\(r.flags) badge=\(r.badgeEnabled)") }
            return
        }
        let restoring = args.contains("restore")
        try snapshot.patched([:]).write(to:folder.appendingPathComponent("before.plist"),options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:folder.appendingPathComponent("before.plist").path)
        let bits: [String: Bool]
        if restoring {
            bits = try JSONDecoder().decode([String:Bool].self,from:Data(contentsOf:journalURL))
            guard Set(bits.keys).isSubset(of:testIDs) else { throw EngineError.invalidJournal }
        } else {
            guard args.contains("suppress"), !FileManager.default.fileExists(atPath:journalURL.path) else { throw EngineError.unavailable("Specify probe/suppress/restore; recover a pending lab session first.") }
            let records = snapshot.records.filter { testIDs.contains($0.id) && $0.badgeEnabled }
            guard !records.isEmpty else { throw EngineError.unavailable("No enabled synthetic test records.") }
            let originals = Dictionary(uniqueKeysWithValues:records.map { ($0.id,$0.badgeEnabled) })
            let data = try JSONEncoder().encode(originals)
            guard FileManager.default.createFile(atPath:journalURL.path,contents:nil,attributes:[.posixPermissions:0o600]) else { throw EngineError.invalidJournal }
            let h=try FileHandle(forWritingTo:journalURL);try h.write(contentsOf:data);try h.synchronize();try h.close()
            bits = Dictionary(uniqueKeysWithValues:records.map { ($0.id,false) })
        }
        let changed = bits.filter { id,bit in snapshot.records.first(where:{$0.id == id}).map{$0.badgeEnabled != bit} ?? false }
        if !changed.isEmpty {
            try await store.write(data:snapshot.patched(changed),expectedFingerprint:snapshot.fingerprint)
            try await UserNotificationRefresher().refresh()
            try await Task.sleep(for:.milliseconds(600))
        }
        let after = try await store.read()
        try after.patched([:]).write(to:folder.appendingPathComponent("after.plist"),options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:folder.appendingPathComponent("after.plist").path)
        print("bitsVerified=\(changed.allSatisfy({id,bit in after.records.first(where:{$0.id==id})?.badgeEnabled==bit})),unrelatedEqual=\(snapshot.preferencesEqual(after,excludingBadgeBitsFor:Set(changed.keys)))")
        guard changed.allSatisfy({ id,bit in after.records.first(where:{$0.id == id})?.badgeEnabled == bit }),
              snapshot.preferencesEqual(after,excludingBadgeBitsFor:Set(changed.keys)) else { throw EngineError.verificationFailed }
        if restoring { try FileManager.default.removeItem(at:journalURL) }
        print("action=\(restoring ? "restore" : "suppress"), changed=\(changed.count), unrelatedPreferencesPreserved=true, diskVerification=pass")
    }
}
