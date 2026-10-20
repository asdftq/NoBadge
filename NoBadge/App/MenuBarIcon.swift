/// Keep the last settled icon while a badge transaction or background check runs.
/// Working is transient; it does not establish that badges have been restored.
struct MenuBarIcon {
  private(set) var symbol = "app"

  @discardableResult mutating func update(phase: DisplayPhase) -> Bool {
    let next: String
    switch phase {
    case .working: return false
    case .hidden: next = "app.badge.checkmark"
    case .paused, .off: next = "pause.circle"
    case .access, .error, .recovery, .unsupported, .focusUnavailable:
      next = "exclamationmark.circle"
    default: next = "app"
    }
    guard next != symbol else { return false }
    symbol = next
    return true
  }
}
