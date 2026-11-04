import CoreGraphics
import ScreenCaptureKit

enum ScrollingScreenSource {
    // The selector passes Quartz global points, whose origin is the primary display's top left.
    static func localRect(_ rect: CGRect, displayFrame: CGRect) -> CGRect? {
        guard !rect.isNull, !rect.isInfinite, rect.width > 0, rect.height > 0,
              rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
              displayFrame.contains(rect) else { return nil }
        return rect.offsetBy(dx: -displayFrame.minX, dy: -displayFrame.minY)
    }

    @MainActor
    static func prepare(
        rect: CGRect, displayID: CGDirectDisplayID, excludingWindows: Set<CGWindowID>
    ) async throws -> ScrollingCaptureSession.CaptureFrame {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScrollingCaptureSession.Failure.displayUnavailable
        }
        guard let local = localRect(rect, displayFrame: display.frame) else {
            throw ScrollingCaptureSession.Failure.invalidRect
        }
        let excluded = content.windows.filter { excludingWindows.contains($0.windowID) }
        let filter = SCContentFilter(display: display, excludingWindows: excluded)
        let configuration = SCScreenshotConfiguration()
        configuration.sourceRect = local
        configuration.width = max(1, Int((local.width * CGFloat(filter.pointPixelScale)).rounded()))
        configuration.height = max(1, Int((local.height * CGFloat(filter.pointPixelScale)).rounded()))
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr
        return {
            let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
            try Task.checkCancellation()
            guard let image = output.sdrImage else { throw ScrollingCaptureSession.Failure.invalidFrame }
            return image
        }
    }
}
