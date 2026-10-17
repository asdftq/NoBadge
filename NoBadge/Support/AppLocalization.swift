import Foundation
import NoBadgeCore

@MainActor enum AppLocalization {
  static var language: AppLanguage = .english
  private static let koreanBundle = Bundle.main.url(forResource: "ko", withExtension: "lproj")
    .flatMap { Bundle(url: $0) }

  static func string(_ key: String) -> String {
    // Source strings are English. Never infer the app language from macOS preferences.
    guard language == .korean else { return key }
    return koreanBundle?.localizedString(forKey: key, value: key, table: nil) ?? key
  }
}

@MainActor func L(_ key: String) -> String { AppLocalization.string(key) }
