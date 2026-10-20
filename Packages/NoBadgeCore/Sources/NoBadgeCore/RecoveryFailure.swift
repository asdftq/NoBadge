import Foundation

public extension Error {
    /// Retry only operational failures. Unknown formats and identities still need
    /// attention; retrying must never bypass the adapters' validation checks.
    var permitsAutomaticRecovery: Bool {
        if let error = self as? EngineError {
            switch error {
            case .invalidSchema, .invalidJournal, .unsupportedOS: return false
            case .concurrentModification, .unavailable, .refreshFailed, .verificationFailed: return true
            }
        }
        let error = self as NSError
        return error.domain == NSPOSIXErrorDomain || error.domain == NSCocoaErrorDomain
    }

    /// No paths, app identifiers, Focus names or localized error contents.
    var recoveryDiagnosticCode: String {
        if let error = self as? EngineError {
            switch error {
            case .invalidSchema: return "invalidSchema"
            case .invalidJournal: return "invalidJournal"
            case .unsupportedOS: return "unsupportedOS"
            case .concurrentModification: return "concurrentModification"
            case .unavailable: return "unavailable"
            case .refreshFailed(let status): return "refreshFailed(\(status))"
            case .verificationFailed: return "verificationFailed"
            }
        }
        let error = self as NSError
        let domain = error.domain == NSPOSIXErrorDomain ? "POSIX" :
            error.domain == NSCocoaErrorDomain ? "Cocoa" : "other"
        return "\(domain)(\(error.code))"
    }
}
