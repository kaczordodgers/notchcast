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

    enum Failure: Error {
        case disabled, permissionDenied, invalidRect, targetUnavailable, encodingFailed, clipboardFailed
    }

    static func isValid(rect: CGRect) -> Bool {
        CaptureAreaSelection.isValid(rect)
    }
}
