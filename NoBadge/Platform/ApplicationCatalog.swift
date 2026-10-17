import AppKit
import Darwin
import NoBadgeCore

struct AppEntry: Identifiable, Equatable, Sendable {
  let id: String
  let name: String
  let url: URL
  var recordIDs: Set<String>
}

actor ApplicationCatalog {
  func load(_ records: [NotificationRecord]) -> [AppEntry] {
    autoreleasepool {
      var groups: [String: AppEntry] = [:]
      for record in records {
        guard
          var url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: record.id)
            ?? record.path.flatMap({ $0.isEmpty ? nil : URL(fileURLWithPath: $0) }),
          Bundle(url: url)?.bundleIdentifier == record.id
        else { continue }
        // Alert/notification helpers belong to their containing application, not separate rows.
        var parent = url.deletingLastPathComponent()
        while parent.path != "/" {
          if parent.pathExtension == "app" { url = parent }
          parent.deleteLastPathComponent()
        }
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
          bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
          bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool != true,
          bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool != true
        else { continue }
        if groups[id] != nil {
          groups[id]?.recordIDs.insert(record.id)
          continue
        }
        let name =
          bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
          ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
          ?? url.deletingPathExtension().lastPathComponent
        groups[id] = AppEntry(id: id, name: name, url: url, recordIDs: [record.id])
      }
      return groups.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
  }
}

actor ApplicationIcons {
  static let shared = ApplicationIcons()
  private let cache = NSCache<NSURL, NSData>()
  init() {
    cache.totalCostLimit = 2 * 1024 * 1024
    cache.countLimit = 128
  }
  func clear() {
    cache.removeAllObjects()
    // Closing the UI releases rows and images, but malloc can retain their empty
    // pages. Return those pages off the main actor before resuming idle operation.
    malloc_zone_pressure_relief(nil, 0)
  }
  func data(for url: URL) -> Data? {
    if let data = cache.object(forKey: url as NSURL) { return data as Data }
    return autoreleasepool {
      let source = NSWorkspace.shared.icon(forFile: url.path)
      var proposed = NSRect(x: 0, y: 0, width: 32, height: 32)
      guard let image = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
        let context = CGContext(
          data: nil, width: 64, height: 64, bitsPerComponent: 8,
          bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return nil }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
      guard let thumbnail = context.makeImage(),
        let data = NSBitmapImageRep(cgImage: thumbnail).representation(using: .png, properties: [:])
      else { return nil }
      cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
      return data
    }
  }
}
