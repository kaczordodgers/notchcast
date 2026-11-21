import CoreGraphics
import Foundation

/// The Mac side of Screenshots, injected so a harness fakes it; `.live` is in `+Live`.
struct ScreenshotSystem: Sendable {
    /// Asks once when not yet granted; true only with Screen Recording access.
    let grantAccess: @MainActor @Sendable () -> Bool
    /// Every display, or only the one holding the point, captured in one pass without `exclusion`.
    let freeze: @MainActor @Sendable (_ under: CGPoint?, _ exclusion: ScreenshotExclusion) async throws
        -> [ScreenshotFrozenDisplay]
    let windows: @MainActor @Sendable () -> [ScreenshotWindow]
    /// Each window's own picture, taken before selection; a window that fails to capture is left out.
    let freezeWindows: @MainActor @Sendable ([UInt32]) async throws -> [UInt32: CGImage]
    let cursor: @MainActor @Sendable () -> CGPoint
    let writeClipboard: @MainActor @Sendable (Data) -> Bool
    let writeText: @MainActor @Sendable (String) -> Bool
    let recognizeText: @Sendable (CGImage) async throws -> [ScreenTextLine]
    /// Pays Vision's one-off model compile in the background; it logs its result and never throws.
    let warmTextRecognition: @Sendable () async -> Void
    let openScreenRecordingSettings: @MainActor @Sendable () -> Void
    let downloads: @Sendable () throws -> URL
    /// The system save panel for Save As; nil when it is cancelled.
    let chooseSaveFile: @MainActor @Sendable (_ suggestedName: String) -> URL?
    /// Shows the selection surface; the returned closure closes it, which answers nil.
    let select: @MainActor @Sendable (
        [ScreenshotFrozenDisplay], [ScreenshotWindow], @escaping @MainActor (ScreenshotRequest?) -> Void
    ) -> @MainActor () -> Void
    /// Opens the editor on a capture and its pixels per point; it answers per way out.
    let edit: @MainActor @Sendable (CGImage, CGFloat, @escaping @MainActor (CaptureEditorOutcome) -> Void)
        -> @MainActor () -> Void
    /// A scrolled area's live picture, prepared once per run; it leaves every window of ours out.
    let openRegion: @MainActor @Sendable (ScrollingCaptureRegion) async throws -> ScreenshotRegionSource
    let uptime: @Sendable () -> TimeInterval
    let pause: @Sendable (TimeInterval) async throws -> Void
    /// The outline over a scrolled area; the returned closure takes it down.
    let showGuide: @MainActor @Sendable (ScrollingCaptureRegion) -> @MainActor () -> Void
}

/// One area's picture on demand; nil when a frame could not be taken.
struct ScreenshotRegionSource: Sendable {
    let image: @Sendable () async -> CGImage?
}
