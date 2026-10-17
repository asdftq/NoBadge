import Foundation
import CoreFoundation
import ObjectiveC
import Testing
@testable import NoBadgeCore

// Independent reference client: usernoted uses NSUserDefaults, rather than the
// low-level CFPreferences current-user source used by the earlier adapter.
private func nativePreferences(identifier: String, container: URL) throws -> UserDefaults {
  typealias Allocate = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
  typealias Initialize = @convention(c) (UnsafeMutableRawPointer, Selector, NSString, NSURL) -> Unmanaged<UserDefaults>?
  let alloc = NSSelectorFromString("alloc")
  let selector = NSSelectorFromString("_initWithSuiteName:container:")
  guard let am = class_getClassMethod(UserDefaults.self, alloc),
    let im = class_getInstanceMethod(UserDefaults.self, selector)
  else { throw EngineError.unsupportedOS }
  let allocate = unsafeBitCast(method_getImplementation(am), to: Allocate.self)
  let initialize = unsafeBitCast(method_getImplementation(im), to: Initialize.self)
  guard let pointer = allocate(UserDefaults.self, alloc),
    let result = initialize(pointer, selector, identifier as NSString, container as NSURL)
  else { throw EngineError.unsupportedOS }
  return result.takeRetainedValue()
}

@Test func restorationUpdatesTheNativeDefaultsSourceUsedByUsernoted() async throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nobadge-native-\(UUID())")
  let preferences = folder.appendingPathComponent("Library/Preferences")
  try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let identifier = "com.asdftq.nobadge.synthetic.\(UUID())"
  let url = preferences.appendingPathComponent(identifier + ".plist")
  let original = try fixture([["bundle-id": "a", "flags": 7], ["bundle-id": "b", "flags": 5]])
  try original.patched([:]).write(to: url)
  let native = try nativePreferences(identifier: identifier, container: folder)
  let hidden = try NotificationSnapshot(data: original.patched(["a": false]))
  let root = try PropertyListSerialization.propertyList(from: hidden.patched([:]), format: nil) as! [String: Any]
  native.set(root["apps"], forKey: "apps")
  #expect(native.synchronize())
  let store = FileNotificationStore(url: url, usePreferencesService: true, useContainerPreferences: true)
  let before = try await store.read()
  #expect(before.flags(for: "a") == 5)
  try await store.write(data: before.patched(["a": true]), expectedFingerprint: before.fingerprint)
  #expect(native.synchronize())
  #expect((native.array(forKey: "apps")?.first as? [String: Any])?["flags"] as? Int == 7)
  #expect(original.preferencesEqual(try await store.read()))
}

@Test func preferenceServiceUpdatesCacheAndPreservesUnrelatedKeys() async throws {
    let folder=FileManager.default.temporaryDirectory.appendingPathComponent("nobadge-preferences-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:folder)}
    let url=folder.appendingPathComponent("preferences.plist")
    let original=try fixture([["bundle-id":"a","flags":7],["bundle-id":"b","flags":5]])
    try original.patched([:]).write(to:url)
    let store=FileNotificationStore(url:url,usePreferencesService:true)
    let domain=url.deletingPathExtension().path as CFString
    _=CFPreferencesSynchronize(domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost)
    _=CFPreferencesCopyValue("apps" as CFString,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost)
    let before=try await store.read()
    try await store.write(data:before.patched(["a":false]),expectedFingerprint:before.fingerprint)
    let hidden=try await store.read()
    #expect(hidden.flags(for:"a")==5)
    #expect(hidden.flags(for:"b")==5)
    #expect(original.preferencesEqual(hidden,excludingBadgeBitsFor:["a"]))
    let cached=CFPreferencesCopyValue("apps" as CFString,domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost) as? [[String:Any]]
    #expect((cached?.first?["flags"] as? NSNumber)?.int64Value==5)
    try await store.write(data:hidden.patched(["a":true]),expectedFingerprint:hidden.fingerprint)
    let restored=try await store.read()
    #expect(original.semanticallyEquals(restored))
}

@Test func containerClientCannotFlushStaleFlagsOverRestoration() async throws {
  let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nobadge-container-\(UUID())")
  let preferences = folder.appendingPathComponent("Library/Preferences")
  try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let identifier = "com.asdftq.nobadge.synthetic.\(UUID())"
  let url = preferences.appendingPathComponent(identifier + ".plist")
  let original = try fixture([["bundle-id": "a", "flags": 7], ["bundle-id": "b", "flags": 5]])
  try original.patched([:]).write(to: url)
  let systemClient = try ContainerPreferences(identifier: identifier, container: folder)
  #expect(systemClient.synchronize())
  _ = systemClient.value(for: "apps")
  let store = FileNotificationStore(url: url, usePreferencesService: true, useContainerPreferences: true)
  let before = try await store.read()
  try await store.write(data: before.patched(["a": false]), expectedFingerprint: before.fingerprint)
  let hidden = try await store.read()
  #expect(hidden.flags(for: "a") == 5)
  #expect((systemClient.value(for: "apps") as? [[String: Any]])?.first?["flags"] as? Int == 5)
  // Leave an independent container client with the old suppressed value, then
  // restore and flush that client. The absolute-path implementation loses this race.
  systemClient.setValue([["bundle-id": "a", "flags": 5], ["bundle-id": "b", "flags": 5]] as NSArray, for: "apps")
  try await store.write(data: hidden.patched(["a": true]), expectedFingerprint: hidden.fingerprint)
  #expect(systemClient.synchronize())
  let restored = try await store.read()
  #expect(original.preferencesEqual(restored))
  #expect(await store.writeCount == 2)
}
