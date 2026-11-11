import Foundation

enum CaptureFailure: Error {
    case permissionDenied, disabled, areaUnavailable, clipboardFailed, captureFailed

    var message: String {
        switch self {
        case .permissionDenied: String(localized: "Screen Recording access is required.", table: "Notchcast")
        case .disabled: String(localized: "Capture is disabled.", table: "Notchcast")
        case .areaUnavailable: String(localized: "Capture area is unavailable.", table: "Notchcast")
        case .clipboardFailed: String(localized: "Could not copy to clipboard.", table: "Notchcast")
        case .captureFailed: String(localized: "Could not capture the screen.", table: "Notchcast")
        }
    }

    init?(_ error: any Error) {
        guard let failure = (error as? any CaptureFailureConvertible)?.captureFailure else { return nil }
        self = failure
    }
}

protocol CaptureFailureConvertible: Error {
    /// nil when the feature words this failure itself.
    var captureFailure: CaptureFailure? { get }
}

extension CaptureFailure: CaptureFailureConvertible {
    var captureFailure: CaptureFailure? { self }
}
