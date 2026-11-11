// notchcast-sources: Tinycast/Features/CaptureArea/Model/CaptureAreaSelection.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/Model/ScreenshotRequest.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Model/RecordingTarget.swift
import CoreGraphics

@main
struct CaptureAreaValidityTest {
    static func main() {
        for rect in [CGRect(x: 0, y: 0, width: 0.5, height: 1),
                     CGRect(x: 0, y: 0, width: 1, height: 0.5),
                     CGRect(x: 0, y: 0, width: -1, height: 1),
                     CGRect(x: CGFloat.infinity, y: 0, width: 1, height: 1), .zero] {
            precondition(!RecordingTarget.isValid(rect), "Recording must reject invalid areas")
            precondition(!ScreenshotRequest.isValid(rect: rect), "Screenshot must reject invalid areas")
        }
        let minimum = CGRect(x: -100, y: -200, width: 1, height: 1)
        precondition(ScreenshotRequest.isValid(rect: minimum) && RecordingTarget.isValid(minimum))
        print("PASS: screenshot and recording reject sub-1pt areas and accept 1x1pt")
    }
}
