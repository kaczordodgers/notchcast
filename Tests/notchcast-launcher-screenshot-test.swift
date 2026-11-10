// notchcast-sources: Tinycast/Features/Notchcast/Launcher/LauncherScreenshotHold.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/CaptureAreaService.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/NSScreen+DisplayID.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift
import AppKit

@main
@MainActor
struct LauncherScreenshotTests {
    static func main() {
        typealias Hold = LauncherScreenshotHold
        let display = CGSize(width: 1512, height: 982)
        let overlay = CGRect(origin: .zero, size: display)
        func keeps(_ windows: [Hold.ScreenWindow], ownOverlay: Bool = false) -> Bool {
            Hold.capturing(windows, displays: [display], ownOverlay: ownOverlay)
        }

        assert(keeps([.init(owner: "com.apple.screencaptureui", bounds: overlay)]), "system screenshot overlay")
        assert(keeps([.init(owner: "screencapture", bounds: overlay)]), "screencapture -i overlay")
        assert(keeps([], ownOverlay: true), "Notchcast area capture")
        assert(!keeps([]), "a click outside or Esc leaves no capture window")
        assert(!keeps([.init(owner: "com.apple.TextEdit", bounds: overlay)]), "switching to another app")
        assert(!keeps([.init(owner: "com.apple.screencaptureui", bounds: CGRect(x: 1300, y: 800, width: 180, height: 120))]),
               "the leftover thumbnail is not a capture in progress")
        assert(!keeps([.init(owner: nil, bounds: overlay)]), "an unnamed full-screen window")

        _ = NSApplication.shared
        assert(!Hold.holds(NSPanel()), "the hook hides when nothing is capturing")
        print("notchcast-launcher-screenshot-test: ok")
    }
}
