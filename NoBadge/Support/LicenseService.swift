import AppKit
import Foundation
import NoBadgeCore
import Security

@MainActor final class LicenseService: ObservableObject {
  @Published private(set) var canUse = false
  @Published private(set) var busy = false
  @Published private(set) var message: String?
  @Published private(set) var maskedKey = ""
  private var credential: LicenseCredential?
  private let api = LicenseAPI()
  private var timer: Timer?
  var changed: (() -> Void)?
  private let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.asdftq.nobadge.license",
    kSecAttrAccount as String: "purchase",
  ]

  init() {
    if BuildDistribution.isSourceBuild {
      canUse = true
      return
    }
    var result: CFTypeRef?
    var read = query
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    if SecItemCopyMatching(read as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let saved = try? JSONDecoder().decode(LicenseCredential.self, from: data) {
      credential = saved
      canUse = saved.permitsUse(productID: LicenseAPI.productID)
      maskedKey = "•••• " + saved.key.suffix(4)
    }
  }

  func start() {
    guard !BuildDistribution.isSourceBuild else { return }
    refreshIfNeeded(force: true)
    timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refreshIfNeeded() }
    }
    timer?.tolerance = 300
  }

  func refreshIfNeeded(force: Bool = false) {
    guard !BuildDistribution.isSourceBuild else { return }
    guard let saved = credential, !busy,
      force || Date().timeIntervalSince(saved.verifiedAt) >= 24 * 3600 else { return }
    busy = true
    Task {
      defer { busy = false }
      do {
        let verified = try await api.validate(saved)
        try persist(verified)
        credential = verified
        message = nil
        setAllowed(verified.permitsUse(productID: LicenseAPI.productID))
      } catch LicenseFailure.unavailable {
        let offline = saved.permitsUse(productID: LicenseAPI.productID)
        message = offline ? L("Your license is active. It will be checked when you are back online.") : L("Connect to the internet to verify your license.")
        setAllowed(offline)
      } catch LicenseFailure.storage {
        message = L(LicenseFailure.storage.localizedDescription)
        setAllowed(saved.permitsUse(productID: LicenseAPI.productID))
      } catch {
        // An explicit invalid/revoked response never falls back to the offline cache.
        credential = nil
        SecItemDelete(query as CFDictionary)
        maskedKey = ""
        message = L("Your license is no longer active. Check your purchase or contact support.")
        setAllowed(false)
      }
    }
  }

  func activate(_ input: String) async -> Bool {
    guard !BuildDistribution.isSourceBuild else { return true }
    guard !busy else { return false }
    let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, key.count <= 256 else { return false }
    busy = true
    message = nil
    defer { busy = false }
    do {
      // A random local label avoids sending the owner's computer/host name.
      let verified = try await api.activate(key: key, instanceName: "NoBadge Mac " + UUID().uuidString.prefix(8))
      do { try persist(verified) }
      catch {
        try? await api.deactivate(verified)
        throw LicenseFailure.storage
      }
      credential = verified
      maskedKey = "•••• " + key.suffix(4)
      setAllowed(true)
      return true
    } catch {
      message = L(error.localizedDescription)
      return false
    }
  }

  func deactivate() async {
    guard !BuildDistribution.isSourceBuild else { return }
    guard let saved = credential, !busy else { return }
    busy = true
    message = nil
    defer { busy = false }
    do {
      try await api.deactivate(saved)
      let result = SecItemDelete(query as CFDictionary)
      guard result == errSecSuccess || result == errSecItemNotFound else { throw LicenseFailure.storage }
      credential = nil
      maskedKey = ""
      setAllowed(false)
    } catch { message = L(error.localizedDescription) }
  }

  private func persist(_ value: LicenseCredential) throws {
    let data = try JSONEncoder().encode(value)
    let attributes = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw LicenseFailure.storage }
    } else if status != errSecSuccess { throw LicenseFailure.storage }
  }

  private func setAllowed(_ value: Bool) {
    canUse = value
    changed?()
  }
}
