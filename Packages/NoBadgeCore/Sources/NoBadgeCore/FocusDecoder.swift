import CoreFoundation
import Foundation

public enum FocusDecoder {
    public static func decode(assertions: Data, configurations: Data? = nil) -> FocusObservation {
        do {
            guard let root = try JSONSerialization.jsonObject(with: assertions) as? [String: Any],
                  let header = root["header"] as? [String: Any], number(header["version"]) == 8,
                  let groups = root["data"] as? [[String: Any]] else {
                return .unknown("unsupportedSchema")
            }
            var candidates: [(id: String, started: Double?)] = []
            for group in groups {
                // macOS may omit the active-record key when only invalidation history remains.
                guard let raw = group["storeAssertionRecords"] else { continue }
                guard let records = raw as? [[String: Any]] else { return .unknown("invalidAssertions") }
                for record in records {
                    guard let details = record["assertionDetails"] as? [String: Any],
                          let id = details["assertionDetailsModeIdentifier"] as? String, !id.isEmpty else {
                        return .unknown("invalidAssertion")
                    }
                    candidates.append((id, number(record["assertionStartDateTimestamp"])))
                }
            }
            let ids = Set(candidates.map(\.id))
            let active: Set<String>
            if ids.count <= 1 {
                active = ids
            } else {
                // Scheduled Focus can overlay an older manual assertion. The most recent
                // assertion is the effective mode, as verified against macOS Focus settings.
                guard candidates.allSatisfy({ ($0.started ?? -1) >= 0 }),
                      let latest = candidates.compactMap(\.started).max() else {
                    return .unknown("ambiguousAssertions")
                }
                let latestIDs = Set(candidates.filter { $0.started == latest }.map(\.id))
                guard latestIDs.count == 1 else { return .unknown("ambiguousAssertions") }
                active = latestIDs
            }
            return .known(activeIDs: active, modes: modes(from: configurations))
        } catch { return .unknown("invalidFocusData") }
    }

    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }

    private static func modes(from data: Data?) -> [FocusMode] {
        guard let data, let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let header = root["header"] as? [String: Any], number(header["version"]) == 3,
              let groups = root["data"] as? [[String: Any]] else { return [] }
        var names: [String: String] = [:]
        for group in groups {
            for (_, value) in group["modeConfigurations"] as? [String: [String: Any]] ?? [:] {
                guard let mode = value["mode"] as? [String: Any],
                      let id = mode["modeIdentifier"] as? String, !id.isEmpty,
                      let name = mode["name"] as? String, !name.isEmpty else { continue }
                names[id] = name
            }
        }
        return names.map { FocusMode(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
