import Foundation

public struct LicenseCredential: Codable, Equatable, Sendable {
  public let key: String
  public let instanceID: String
  public let productID: Int
  public var verifiedAt: Date
  public let expiresAt: Date?

  public init(key: String, instanceID: String, productID: Int, verifiedAt: Date, expiresAt: Date?) {
    self.key = key
    self.instanceID = instanceID
    self.productID = productID
    self.verifiedAt = verifiedAt
    self.expiresAt = expiresAt
  }

  public func permitsUse(productID: Int, now: Date = .now) -> Bool {
    self.productID == productID && !instanceID.isEmpty && !key.isEmpty
      && now.timeIntervalSince(verifiedAt) >= -300
      && now.timeIntervalSince(verifiedAt) < 30 * 24 * 3600
      && (expiresAt.map { $0 > now } ?? true)
  }
}

public enum LicenseFailure: Error, LocalizedError, Sendable {
  case unavailable, invalid, wrongProduct, activationLimit, storage
  public var errorDescription: String? {
    switch self {
    case .unavailable: "Cannot reach the license service. Check your connection and try again."
    case .invalid: "This license is not valid. Check the key in your purchase receipt."
    case .wrongProduct: "This key belongs to a different product. Use your NoBadge license key."
    case .activationLimit: "This key has no available activations. Deactivate another Mac or contact support."
    case .storage: "NoBadge could not save your license in Keychain. Please try again."
    }
  }
}

public struct LicenseResponse: Decodable, Sendable {
  public let activated: Bool?
  public let valid: Bool?
  public let deactivated: Bool?
  public let error: String?
  public let license_key: Key?
  public let instance: Instance?
  public let meta: Metadata?
  public struct Key: Decodable, Sendable {
    public let status: String
    public let key: String
    public let expires_at: String?
  }
  public struct Instance: Decodable, Sendable { public let id: String }
  public struct Metadata: Decodable, Sendable { public let product_id: Int }

  public func checked(productID: Int, key: String, instanceID: String? = nil) throws {
    guard meta?.product_id == productID else { throw LicenseFailure.wrongProduct }
    guard let license_key,
      ["active", "inactive"].contains(license_key.status),
      license_key.key.caseInsensitiveCompare(key) == .orderedSame
    else { throw LicenseFailure.invalid }
    if let instanceID, instance?.id != instanceID { throw LicenseFailure.invalid }
  }

  public var expiry: Date? {
    guard let value = license_key?.expires_at else { return nil }
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions.insert(.withFractionalSeconds)
    return formatter.date(from: value) ?? .distantPast
  }
}

public actor LicenseAPI {
  public static let productID = 1444435
  private let session: URLSession
  public init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20
    configuration.httpCookieStorage = nil
    session = URLSession(configuration: configuration)
  }

  public func activate(key: String, instanceName: String) async throws -> LicenseCredential {
    // Check the product before consuming an activation on another product's key.
    let validation = try await request("validate", ["license_key": key])
    guard validation.valid == true else { throw LicenseFailure.invalid }
    try validation.checked(productID: Self.productID, key: key)
    let response = try await request("activate", ["license_key": key, "instance_name": instanceName])
    guard response.activated == true else {
      if response.error?.localizedCaseInsensitiveContains("limit") == true {
        throw LicenseFailure.activationLimit
      }
      throw LicenseFailure.invalid
    }
    try response.checked(productID: Self.productID, key: key)
    guard let instance = response.instance, !instance.id.isEmpty else { throw LicenseFailure.invalid }
    return LicenseCredential(key: key, instanceID: instance.id, productID: Self.productID,
      verifiedAt: .now, expiresAt: response.expiry)
  }

  public func validate(_ credential: LicenseCredential) async throws -> LicenseCredential {
    let response = try await request("validate", ["license_key": credential.key, "instance_id": credential.instanceID])
    guard response.valid == true else { throw LicenseFailure.invalid }
    try response.checked(productID: Self.productID, key: credential.key, instanceID: credential.instanceID)
    return LicenseCredential(key: credential.key, instanceID: credential.instanceID,
      productID: Self.productID, verifiedAt: .now, expiresAt: response.expiry)
  }

  public func deactivate(_ credential: LicenseCredential) async throws {
    let response = try await request("deactivate", ["license_key": credential.key, "instance_id": credential.instanceID])
    guard response.deactivated == true else { throw LicenseFailure.invalid }
  }

  private func request(_ action: String, _ fields: [String: String]) async throws -> LicenseResponse {
    var request = URLRequest(url: URL(string: "https://api.lemonsqueezy.com/v1/licenses/" + action)!)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "+&=?#")
    request.httpBody = fields.sorted { $0.key < $1.key }.map {
      $0.key + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    }.joined(separator: "&").data(using: .utf8)
    let data: Data
    let response: URLResponse
    do { (data, response) = try await session.data(for: request) }
    catch { throw LicenseFailure.unavailable }
    guard let http = response as? HTTPURLResponse, http.statusCode < 500,
      http.statusCode != 429 else { throw LicenseFailure.unavailable }
    guard let decoded = try? JSONDecoder().decode(LicenseResponse.self, from: data) else {
      if (200..<300).contains(http.statusCode) { throw LicenseFailure.unavailable }
      throw LicenseFailure.invalid
    }
    return decoded
  }
}
