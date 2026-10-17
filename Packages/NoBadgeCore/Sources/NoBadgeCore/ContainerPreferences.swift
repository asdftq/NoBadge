import CoreFoundation
import Foundation
import ObjectiveC

/// Use the same defaults client as usernoted. Low-level current-user CF sources
/// can maintain a different cache for the same container file. This SPI remains
/// confined to the explicitly qualified private adapter.
struct ContainerPreferences {
  private typealias Allocate = @convention(c) (AnyClass, Selector) -> UnsafeMutableRawPointer?
  private typealias Initialize = @convention(c) (
    UnsafeMutableRawPointer, Selector, NSString, NSURL
  ) -> Unmanaged<UserDefaults>?
  private let preferences: UserDefaults

  init(identifier: String, container: URL) throws {
    let alloc = NSSelectorFromString("alloc")
    let selector = NSSelectorFromString("_initWithSuiteName:container:")
    guard let allocation = class_getClassMethod(UserDefaults.self, alloc),
      let initialization = class_getInstanceMethod(UserDefaults.self, selector)
    else { throw EngineError.unsupportedOS }
    let allocate = unsafeBitCast(method_getImplementation(allocation), to: Allocate.self)
    let initialize = unsafeBitCast(method_getImplementation(initialization), to: Initialize.self)
    // Keep alloc/init ownership unmanaged until init returns its +1 object.
    // Swift must not release an uninitialized allocation if init replaces it.
    guard let pointer = allocate(UserDefaults.self, alloc),
      let initialized = initialize(
        pointer, selector, identifier as NSString,
        container.resolvingSymlinksInPath() as NSURL)
    else { throw EngineError.unsupportedOS }
    preferences = initialized.takeRetainedValue()
  }
  func synchronize() -> Bool {
    preferences.synchronize()
  }
  func value(for key: String) -> CFTypeRef? {
    preferences.object(forKey: key).map { $0 as CFTypeRef }
  }
  func setValue(_ value: CFTypeRef, for key: String) {
    preferences.set(value, forKey: key)
  }
}
