import Foundation

actor DiagnosticLogger {
  private let folder: URL
  private let version: String
  private let build: String
  init(root: URL, version: String, build: String) {
    folder = root.appendingPathComponent("logs")
    self.version = version
    self.build = build
  }
  func record(state: String, count: Int, failure: String = "", statusSymbol: String = "") {
    guard count >= 0, state.count < 32 else { return }
    do {
      try FileManager.default.createDirectory(
        at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      formatter.dateFormat = "yyyy-MM-dd"
      let file = folder.appendingPathComponent(formatter.string(from: .now) + ".jsonl")
      var event: [String: Any] = [
        "time": ISO8601DateFormatter().string(from: .now), "version": version, "osBuild": build,
        "state": state, "ownedCount": count,
      ]
      if !statusSymbol.isEmpty { event["statusSymbol"] = statusSymbol }
      if !failure.isEmpty { event["failure"] = String(failure.prefix(256)) }
      var data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
      data.append(0x0A)
      if !FileManager.default.fileExists(atPath: file.path) {
        FileManager.default.createFile(
          atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
      }
      let handle = try FileHandle(forWritingTo: file)
      try handle.seekToEnd()
      try handle.write(contentsOf: data)
      try handle.close()
      let files = try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
      ).filter { $0.pathExtension == "jsonl" }.sorted {
        $0.lastPathComponent > $1.lastPathComponent
      }
      var total = 0
      for item in files {
        let values = try item.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let age = Date().timeIntervalSince(values.contentModificationDate ?? .distantPast)
        total += values.fileSize ?? 0
        if age > 7 * 86400 || total > 1_048_576 { try FileManager.default.removeItem(at: item) }
      }
    } catch { /* Diagnostics must never make badge restoration fail. */  }
  }
  func recent() -> String {
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: nil)
    else { return "" }
    return files.filter { $0.pathExtension == "jsonl" }.sorted {
      $0.lastPathComponent < $1.lastPathComponent
    }.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined()
  }
}
