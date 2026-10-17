import Foundation
import Testing
@testable import NoBadgeCore

actor MemoryStore: NotificationStore {
    var value: NotificationSnapshot
    var writes=0
    var reads=0
    var failWrite=false
    init(_ value: NotificationSnapshot) {self.value=value}
    func read() -> NotificationSnapshot {reads+=1;return value}
    func write(data:Data,expectedFingerprint:String) throws {
        if failWrite {throw EngineError.concurrentModification}
        guard value.fingerprint==expectedFingerprint else {throw EngineError.concurrentModification}
        value=try NotificationSnapshot(data:data);writes+=1
    }
    func externallySet(_ bits:[String:Bool]) throws {value=try NotificationSnapshot(data:value.patched(bits))}
    func replace(_ snapshot:NotificationSnapshot) {value=snapshot}
    func failNextWrite() {failWrite=true}
}
actor MemoryJournal: JournalPersistence {
    var value:RecoveryJournal?
    var failSave=false
    var saves=0
    func load() -> RecoveryJournal? {value}
    func save(_ j:RecoveryJournal) throws {if failSave {throw EngineError.unavailable("disk full")};value=j;saves+=1}
    func clear() {value=nil}
    func failSaves() {failSave=true}
}
actor MemoryRefresh: DaemonRefreshing {
    var count=0
    var fail=false
    func refresh() throws {count+=1;if fail {throw EngineError.refreshFailed(1)}}
    func setFailure(_ x:Bool) {fail=x}
}
func makeEngine(_ store:MemoryStore,_ journal:MemoryJournal,_ refresh:MemoryRefresh) -> BadgeEngine {
    BadgeEngine(store:store,journals:journal,refresher:refresh,version:"test",osBuild:"25F80",verificationDelay:.zero,refreshInterval:0)
}
@Test func idleAndPreviouslyOffAreActualNoOps() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":5]]));let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    for _ in 0..<100 {_=try await e.reconcile(hidden:false,qualified:true)}
    _=try await e.reconcile(hidden:true,qualified:true)
    #expect(await store.writes==0);#expect(await r.count==0);#expect(await j.saves==0)
}
@Test func hundredCyclesPreserveDisabledAndUnrelatedSettings() async throws {
    let baseline=try fixture([["bundle-id":"a","flags":7],["bundle-id":"b","flags":5]])
    let store=MemoryStore(baseline);let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    for _ in 0..<100 {
        #expect(try await e.reconcile(hidden:true,qualified:true).hiddenCount==1)
        _=try await e.restore()
        #expect(baseline.semanticallyEquals(await store.value))
    }
    #expect(await r.count==200);#expect(await j.value==nil)
}
@Test func journalFailurePreventsAllSystemWrites() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7]]));let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    await j.failSaves()
    await #expect(throws:(any Error).self) {try await e.reconcile(hidden:true,qualified:true)}
    #expect(await store.writes==0);#expect(await r.count==0)
}
@Test func refreshFailureRetainsRecoveryAndRelaunchRestores() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7]]));let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    await r.setFailure(true)
    await #expect(throws:EngineError.refreshFailed(1)) {try await e.reconcile(hidden:true,qualified:true)}
    #expect(await j.value?.phase=="needsRecovery");#expect(await store.value.flags(for:"a")==5)
    await r.setFailure(false)
    let relaunched=makeEngine(store,j,r);_=try await relaunched.restore()
    #expect(await store.value.flags(for:"a")==7);#expect(await j.value==nil)
}
@Test func externalOnDecisionIsNotSuppressedAgain() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7]]));let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    _=try await e.reconcile(hidden:true,qualified:true)
    try await store.externallySet(["a":true])
    #expect(try await e.reconcile(hidden:true,qualified:true).hiddenCount==0)
    _=try await e.reconcile(hidden:true,qualified:true)
    #expect(await store.value.flags(for:"a")==7);#expect(await store.writes==1)
}
@Test func exceptionsCanBeAddedAndRemovedInSameSession() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7],["bundle-id":"b","flags":7]]));let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    _=try await e.reconcile(hidden:true,qualified:true)
    #expect(try await e.reconcile(hidden:true,exceptions:["a"],qualified:true).hiddenCount==1)
    #expect(await store.value.flags(for:"a")==7)
    #expect(try await e.reconcile(hidden:true,qualified:true).hiddenCount==2)
    #expect(await store.value.flags(for:"a")==5)
    _=try await e.restore();#expect(await store.value.flags(for:"a")==7)
}
@Test func restorationMergesNewUnrelatedBits() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7],["bundle-id":"b","flags":5]]));let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    _=try await e.reconcile(hidden:true,qualified:true)
    await store.replace(try fixture([["bundle-id":"a","flags":13],["bundle-id":"b","flags":5]]))
    _=try await e.restore();#expect(await store.value.flags(for:"a")==15);#expect(await store.value.flags(for:"b")==5)
}
@Test func concurrentRequestsAreSerializedAcrossSuspensionPoints() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7]]));let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    try await withThrowingTaskGroup(of:Void.self) {group in
        for _ in 0..<20 {group.addTask {_=try await e.reconcile(hidden:true,qualified:true)}}
        try await group.waitForAll()
    }
    #expect(await store.writes==1);#expect(await r.count==1)
    _=try await e.restore()
}
@Test func failedFingerprintWriteDoesNotOwnAnUntouchedBit() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7]]));let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    await store.failNextWrite()
    await #expect(throws:EngineError.concurrentModification) {try await e.reconcile(hidden:true,qualified:true)}
    #expect(await j.value==nil);#expect(await r.count==0)
}
@Test func unknownOSCannotSuppress() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7]]));let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    await #expect(throws:EngineError.unsupportedOS) {try await e.reconcile(hidden:true,qualified:false)}
    #expect(await store.writes==0)
}
@Test func corruptJournalIsKeptAndBlocksRecovery() async throws {
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("journal.json");try Data("broken".utf8).write(to:url);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    let j=FileJournalStore(url:url)
    await #expect(throws:EngineError.invalidJournal) {try await j.load()}
    #expect(FileManager.default.fileExists(atPath:url.path))
}
@Test func realJournalRoundTripAndMode() async throws {
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer {try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("journal.json");let j=FileJournalStore(url:url);var data=RecoveryJournal(version:"test",osBuild:"25F80");data.entries["a"]=JournalEntry(bundleID:"a",originalBadgeEnabled:true)
    try await j.save(data);#expect(try await j.load()==data)
    #expect((try FileManager.default.attributesOfItem(atPath:url.path)[.posixPermissions] as? NSNumber)?.intValue==0o600)
    try await j.clear();#expect(try await j.load()==nil)
}
@Test func daemonMetadataMayRefreshButUnknownSettingsStayStrict() throws {
    let a=try fixture([["bundle-id":"a","flags":7,"src":[1],"push":["token":"one"],"future-setting":"keep"],["bundle-id":"b","flags":5]])
    let b=try fixture([["bundle-id":"b","flags":5],["bundle-id":"a","flags":5,"src":[2],"push":["token":"two"],"future-setting":"keep"]])
    #expect(a.preferencesEqual(b,excludingBadgeBitsFor:["a"]))
    let c=try fixture([["bundle-id":"b","flags":5],["bundle-id":"a","flags":5,"future-setting":"lost"]])
    #expect(!a.preferencesEqual(c,excludingBadgeBitsFor:["a"]))
}

@Test func restorePreemptsSuppressionCooldown() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7]]));let j=MemoryJournal();let r=MemoryRefresh()
    let e=BadgeEngine(store:store,journals:j,refresher:r,version:"test",osBuild:"25F80",verificationDelay:.zero,refreshInterval:10)
    _=try await e.reconcile(hidden:true,qualified:true)
    let repeated=Task {try await e.reconcile(hidden:true,qualified:true)}
    try await Task.sleep(for:.milliseconds(20))
    let start=ContinuousClock.now
    _=try await e.restore();_=try await repeated.value
    #expect(ContinuousClock.now-start < .seconds(1))
    #expect(await store.value.flags(for:"a")==7)
    #expect(await store.writes==2)
}
@Test func aRemovedOwnedAppIsNotRecreated() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7]]));let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    _=try await e.reconcile(hidden:true,qualified:true)
    await store.replace(try fixture([]))
    _=try await e.restore();#expect(await store.value.records.isEmpty);#expect(await j.value==nil);#expect(await store.writes==1)
}

@Test func unqualifiedOSUpgradeKeepsRecoveryJournalWithoutWrites() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7]]));let j=MemoryJournal();let r=MemoryRefresh();let e=makeEngine(store,j,r)
    _=try await e.reconcile(hidden:true,qualified:true)
    let upgraded=BadgeEngine(store:store,journals:j,refresher:r,version:"new",osBuild:"UNQUALIFIED",verificationDelay:.zero,refreshInterval:0)
    await #expect(throws:EngineError.unsupportedOS) {try await upgraded.restore()}
    #expect(await j.value != nil);#expect(await store.writes==1)
    _=try await e.restore()
}

@Test func quitPriorityDrainsSuppressionBeforeFinalRestore() async throws {
    let store=MemoryStore(try fixture([["bundle-id":"a","flags":7]]));let j=MemoryJournal();let r=MemoryRefresh()
    let engine=BadgeEngine(store:store,journals:j,refresher:r,version:"test",osBuild:"25F80",verificationDelay:.zero,refreshInterval:10)
    _=try await engine.reconcile(hidden:true,qualified:true)
    let pending=Task {try await engine.reconcile(hidden:true,qualified:true)}
    try await Task.sleep(for:.milliseconds(20))
    let start=ContinuousClock.now
    await engine.prioritizeRestoration()
    #expect(try await pending.value.wrote == false)
    _=try await engine.restore()
    #expect(start.duration(to:.now) < .seconds(1))
    #expect(await store.value.flags(for:"a")==7)
    #expect(await j.value == nil)
}
