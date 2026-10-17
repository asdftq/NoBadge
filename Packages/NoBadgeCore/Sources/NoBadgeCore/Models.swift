import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case korean = "ko"
}

public struct UserSettings: Codable, Equatable, Sendable {
    public static let currentSetupRevision = 1
    public var setupRevision: Int? = nil
    public var needsSetup: Bool { !onboardingComplete || setupRevision != Self.currentSetupRevision }
    public var schemaVersion = 1
    public var onboardingComplete = false
    public var setupStep: Int? = nil
    public var automationEnabled = false
    public var selectedFocusIDs: Set<String>? = nil
    public var exceptionBundleIDs: Set<String> = []
    public var pauseUntil: Date?
    public var manualHideUntil: Date?
    public var automaticUpdateChecks = true
    public var updatePreferencesRevision: Int? = nil
    // Optional for settings saved before the language picker existed.
    public var languageCode: String? = nil
    public var appLanguage: AppLanguage {
        get { AppLanguage(rawValue: languageCode ?? "") ?? .english }
        set { languageCode = newValue.rawValue }
    }
    public init() {}
    public mutating func normalizeDeadlines(now: Date) {
        if let deadline = pauseUntil, deadline <= now || deadline.timeIntervalSince(now) > 900 { pauseUntil = nil }
        if let deadline = manualHideUntil, deadline <= now || deadline.timeIntervalSince(now) > 1800 { manualHideUntil = nil }
    }
    /// A continuous timer may expire while the wall clock is still behind its
    /// original UTC deadline. Only expire the intent that scheduled that timer.
    public mutating func expireDeadlines(pause: Date?, manualHide: Date?) {
        if let pause, pauseUntil == pause { pauseUntil = nil }
        if let manualHide, manualHideUntil == manualHide { manualHideUntil = nil }
    }
}

public struct FocusMode: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum FocusObservation: Equatable, Sendable {
    case known(activeIDs: Set<String>, modes: [FocusMode])
    case unknown(String)
    public var activeIDs: Set<String>? {
        if case let .known(ids, _) = self { return ids }; return nil
    }
    public var modes: [FocusMode] {
        if case let .known(_, modes) = self { return modes }; return []
    }
    public var displayName: String {
        guard let ids = activeIDs, !ids.isEmpty else { return "Focus" }
        return modes.first(where: { ids.contains($0.id) })?.name ?? "Focus"
    }
}

public enum DesiredState: Equatable, Sendable { case visible, hidden, unknown }
public enum PolicyReducer {
    public static func desired(settings: UserSettings, focus: FocusObservation, now: Date, capable: Bool, recoveryPending: Bool) -> DesiredState {
        guard capable, !recoveryPending else { return .visible }
        if let deadline = settings.pauseUntil, deadline > now { return .visible }
        if let deadline = settings.manualHideUntil, deadline > now { return .hidden }
        guard !settings.needsSetup, settings.automationEnabled else { return .visible }
        guard let ids = focus.activeIDs else { return .unknown }
        if let selected = settings.selectedFocusIDs { return !ids.isDisjoint(with: selected) ? .hidden : .visible }
        return ids.isEmpty ? .visible : .hidden
    }
}
