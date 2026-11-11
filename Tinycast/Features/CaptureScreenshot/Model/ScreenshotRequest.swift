import Foundation

enum ScreenshotRequest: Sendable {
    // Quartz global points have their origin at the primary display's top left.
    case rect(CGRect)
    case window(UInt32)
    case display(UInt32)

    enum Destination: Sendable {
        case clipboard
        case file(folder: URL? = nil)
        case both(folder: URL? = nil)
    }

    enum Failure: CaptureFailureConvertible {
        case disabled, permissionDenied, invalidRect, targetUnavailable, encodingFailed, clipboardFailed

        var captureFailure: CaptureFailure? {
            switch self {
            case .permissionDenied: .permissionDenied
            case .clipboardFailed: .clipboardFailed
            case .disabled: .disabled
            case .invalidRect, .targetUnavailable: .areaUnavailable
            case .encodingFailed: .captureFailed
            }
        }
    }

    static func isValid(rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
    }
}
