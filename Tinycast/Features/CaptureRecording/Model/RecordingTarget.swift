import Foundation

enum RecordingTarget: Sendable, Equatable {
    // Rectangles use Quartz global points, matching CaptureAreaSelection.rect.
    case area(CGRect)
    case window(UInt32)
    case display(UInt32)

    enum Failure: CaptureFailureConvertible, Equatable {
        case disabled, busy, invalidTarget, permissionDenied, targetUnavailable
        case writerFailed, noFrames, notRecording, invalidFolder

        var captureFailure: CaptureFailure? {
            switch self {
            case .permissionDenied: .permissionDenied
            case .disabled: .disabled
            case .invalidTarget, .targetUnavailable: .areaUnavailable
            case .busy, .writerFailed, .noFrames, .notRecording, .invalidFolder: nil
            }
        }
    }

    static func isValid(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite)
            && rect.size.width >= 1 && rect.size.height >= 1
    }
}
