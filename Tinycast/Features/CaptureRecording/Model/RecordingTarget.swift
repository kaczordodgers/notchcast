import Foundation

enum RecordingTarget: Sendable, Equatable {
    // Rectangles use Quartz global points, matching CaptureAreaSelection.rect.
    case area(CGRect)
    case window(UInt32)
    case display(UInt32)

    enum Failure: Error, Equatable {
        case disabled, busy, invalidTarget, permissionDenied, targetUnavailable
        case writerFailed, noFrames, notRecording, invalidFolder
    }

    static func isValid(_ rect: CGRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite)
            && rect.size.width >= 1 && rect.size.height >= 1
    }
}
