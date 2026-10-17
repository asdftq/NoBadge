import Foundation
import CoreFoundation
import CryptoKit

public enum EngineError: Error, LocalizedError, Equatable, Sendable {
    case invalidSchema, concurrentModification, invalidJournal, unavailable(String), refreshFailed(Int32), verificationFailed, unsupportedOS
    public var errorDescription: String? {
        switch self {
        case .invalidSchema: "These macOS settings have changed. Automatic hiding is paused."
        case .concurrentModification: "Your notification settings changed. NoBadge paused to keep them safe."
        case .invalidJournal: "Saved recovery information could not be read."
        case .unavailable(let reason): reason
        case .refreshFailed, .verificationFailed: "Badge settings could not be confirmed."
        case .unsupportedOS: "This macOS version needs a compatibility update."
        }
    }
}

public struct NotificationRecord: Equatable, Identifiable, Sendable {
    public let id: String
    public let flags: Int64
    public let path: String?
    public var badgeEnabled: Bool { flags & 2 != 0 }
}

/// Immutable property-list tree. Only narrow pure patch functions can create a new tree.
public struct NotificationSnapshot: @unchecked Sendable {
    private let root: [String: Any]
    private let format: PropertyListSerialization.PropertyListFormat
    public let fingerprint: String
    public let records: [NotificationRecord]
    public let schemaVersion: Int64?
    public init(data: Data) throws {
        var format = PropertyListSerialization.PropertyListFormat.binary
        guard let root = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any],
              let apps = root["apps"] as? [[String: Any]] else { throw EngineError.invalidSchema }
        var records: [NotificationRecord] = []; var seen: Set<String> = []
        for app in apps {
            guard let id = app["bundle-id"] as? String, !id.isEmpty,
                  let number = app["flags"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  !["f", "d"].contains(String(cString: number.objCType)) else { throw EngineError.invalidSchema }
            guard seen.insert(id).inserted else { throw EngineError.invalidSchema }
            records.append(NotificationRecord(id: id, flags: number.int64Value, path: app["path"] as? String))
        }
        self.schemaVersion = (root["version"] as? NSNumber)?.int64Value
        self.root = root; self.format = format; self.fingerprint = Self.hash(data); self.records = records
    }
    public func flags(for id: String) -> Int64? { records.first(where: { $0.id == id })?.flags }
    public func patched(_ bits: [String: Bool]) throws -> Data {
        var tree = root; var apps = root["apps"] as! [[String: Any]]
        for index in apps.indices {
            let id = apps[index]["bundle-id"] as! String
            guard let bit = bits[id] else { continue }
            let flags = (apps[index]["flags"] as! NSNumber).int64Value
            apps[index]["flags"] = NSNumber(value: (flags & ~2) | (bit ? 2 : 0))
        }
        tree["apps"] = apps
        return try PropertyListSerialization.data(fromPropertyList: tree, format: format, options: 0)
    }
    public func semanticallyEquals(_ other: NotificationSnapshot, excludingBadgeBitsFor ids: Set<String> = []) -> Bool {
        func normalized(_ tree: [String: Any]) -> NSDictionary {
            var copy = tree; var apps = copy["apps"] as! [[String: Any]]
            for i in apps.indices where ids.contains(apps[i]["bundle-id"] as! String) {
                apps[i]["flags"] = NSNumber(value: (apps[i]["flags"] as! NSNumber).int64Value & ~2)
            }
            copy["apps"] = apps; return copy as NSDictionary
        }
        return normalized(root).isEqual(to: normalized(other.root) as! [AnyHashable: Any])
    }
    /// usernoted refreshes registration sources/push tokens and reorders records.
    /// These are daemon-owned metadata, not user notification preferences.
    /// Unknown fields, user settings, and unexpected record deletion remain strict.
    public func preferencesEqual(_ other: NotificationSnapshot, excludingBadgeBitsFor ids: Set<String> = []) -> Bool {
        func normalized(_ tree: [String: Any]) -> NSDictionary {
            var copy = tree
            var apps = copy["apps"] as! [[String: Any]]
            // Observed on 25F80: IDS re-registers this legacy service record,
            // then usernoted prunes it. The real Messages preference is MobileSMS.
            apps.removeAll {
                ($0["bundle-id"] as? String) == "com.apple.iChat" &&
                ($0["path"] as? String) == "/System/Library/PrivateFrameworks/IDS.framework/identityservicesd.app" &&
                $0["auth"] == nil && !ids.contains("com.apple.iChat")
            }
            for i in apps.indices {
                apps[i].removeValue(forKey: "src")
                if var push = apps[i]["push"] as? [String: Any] { push.removeValue(forKey: "token"); apps[i]["push"] = push }
                if ids.contains(apps[i]["bundle-id"] as! String) {
                    apps[i]["flags"] = NSNumber(value: (apps[i]["flags"] as! NSNumber).int64Value & ~2)
                }
            }
            apps.sort { ($0["bundle-id"] as! String) < ($1["bundle-id"] as! String) }
            copy["apps"] = apps
            return copy as NSDictionary
        }
        return normalized(root).isEqual(to: normalized(other.root) as! [AnyHashable: Any])
    }
    /// Cache agreement is strict for every preference bit and unknown field.
    /// Known daemon registration metadata may lag behind the on-disk snapshot.
    func preferencesMatchCachedApplications(_ apps: [[String: Any]]) throws -> Bool {
        var cachedRoot = root
        cachedRoot["apps"] = apps
        let data = try PropertyListSerialization.data(fromPropertyList: cachedRoot, format: format, options: 0)
        return preferencesEqual(try NotificationSnapshot(data: data))
    }
    public static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
