import AppKit

/// A screenshot taking key leaves the launcher up, and the launcher takes key back after it, so a click outside
/// still dismisses it.
@MainActor
enum LauncherScreenshotHold {
    struct ScreenWindow {
        var owner: String?
        var bounds: CGRect
    }

    nonisolated static let captureOwners: Set<String> = [
        "com.apple.screencaptureui", "screencaptureui", "screencapture",
    ]
    private static var watch: Task<Void, Never>?

    /// The selection overlay spans a whole display; the thumbnail left after a capture does not.
    nonisolated static func capturing(_ windows: [ScreenWindow], displays: [CGSize], ownOverlay: Bool) -> Bool {
        ownOverlay || windows.contains { window in
            window.owner.map(captureOwners.contains) == true
                && displays.contains { window.bounds.width >= $0.width && window.bounds.height >= $0.height }
        }
    }

    static func holds(_ panel: NSWindow) -> Bool {
        guard capturing() else { return false }
        watch?.cancel()
        watch = Task { [weak panel] in
            while !Task.isCancelled, panel?.isVisible == true, capturing() {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled, let panel, panel.isVisible, !panel.isKeyWindow else { return }
            panel.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private static func capturing() -> Bool {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let windows = info.map { entry in
            let pid = entry[kCGWindowOwnerPID as String] as? pid_t
            let bounds = (entry[kCGWindowBounds as String] as? NSDictionary)
                .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
            return ScreenWindow(
                owner: pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
                    ?? entry[kCGWindowOwnerName as String] as? String,
                bounds: bounds)
        }
        let ownOverlay = NSApp.windows.contains { $0 is CaptureAreaService.OverlayWindow && $0.isVisible }
        return capturing(windows, displays: NSScreen.screens.map(\.frame.size), ownOverlay: ownOverlay)
    }
}
