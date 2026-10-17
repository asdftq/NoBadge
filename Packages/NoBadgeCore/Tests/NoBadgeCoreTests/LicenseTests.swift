import Foundation
import Testing
@testable import NoBadgeCore

@Test func licenseCacheRequiresThePurchasedProductAndExpiresOffline() {
  let now = Date()
  let credential = LicenseCredential(key: "key", instanceID: "mac", productID: LicenseAPI.productID,
    verifiedAt: now, expiresAt: nil)
  #expect(credential.permitsUse(productID: LicenseAPI.productID, now: now))
  #expect(!credential.permitsUse(productID: 1437051, now: now))
  #expect(!credential.permitsUse(productID: LicenseAPI.productID, now: now.addingTimeInterval(30 * 86400)))
}

@Test func licenseResponseRejectsAnotherProductOrActivation() throws {
  let data = Data(#"{"valid":true,"license_key":{"status":"active","key":"key"},"instance":{"id":"mac"},"meta":{"product_id":1444435}}"#.utf8)
  let response = try JSONDecoder().decode(LicenseResponse.self, from: data)
  try response.checked(productID: LicenseAPI.productID, key: "key", instanceID: "mac")
  #expect(throws: (any Error).self) { try response.checked(productID: 1437051, key: "key", instanceID: "mac") }
  #expect(throws: (any Error).self) { try response.checked(productID: LicenseAPI.productID, key: "key", instanceID: "another-mac") }
}
