#if DEBUG
import AppKit

/// Drives the real app on a real display for a screen recording, Debug builds only:
/// `NOTCHCAST_LIVE_DEMO=open|music`, `NOTCHCAST_LIVE_DEMO_SCREEN=builtin|external`, and an optional
/// `NOTCHCAST_LIVE_DEMO_QUERY`. It waits for the island, opens the launcher from it, types the query, closes it,
/// then quits. Each step prints `demo: <step> <seconds since launch>` so frames can be matched to it.
@MainActor
enum NotchcastLiveDemo {
    static func runIfRequested(_ core: AppCore) {
        let environment = ProcessInfo.processInfo.environment
        guard let scenario = environment["NOTCHCAST_LIVE_DEMO"] else { return }
        let builtin = environment["NOTCHCAST_LIVE_DEMO_SCREEN"] != "external"
        let query = environment["NOTCHCAST_LIVE_DEMO_QUERY"] ?? "sa"
        NotchcastLauncherSurface.preferredScreen = NSScreen.screens.first {
            ($0.safeAreaInsets.top > 0) == builtin
        } ?? (builtin ? NSScreen.screens.first : nil)
        let start = ProcessInfo.processInfo.systemUptime
        @MainActor func step(_ name: String, after seconds: Double) async {
            try? await Task.sleep(for: .seconds(seconds))
            print(String(format: "demo: %@ %.3f", name, ProcessInfo.processInfo.systemUptime - start))
            for window in NSApp.windows where window.isVisible {
                print("demo:   ", type(of: window), window.level.rawValue, window.alphaValue, window.frame,
                      window.isKeyWindow)
            }
            fflush(stdout)
        }
        if let screen = NotchcastLauncherSurface.preferredScreen ?? NSScreen.screens.first {
            backdrop = wallpaper(on: screen)
        }
        Task { @MainActor in
            await step("launched", after: 0)
            // A launch from the terminal counts as the user's and opens the launcher; the demo starts at rest.
            core.paletteCoordinator.hidePalette()
            await step("ready", after: 4)
            if scenario == "music" {
                IslandController.shared.demoTrack = IslandTrack(
                    title: "Teardrop", artist: "Massive Attack", artwork: artwork, isPlaying: true)
                await step("music", after: 2.5)
            }
            await step("open", after: 1.5)
            NotchcastLauncher.open()
            await step("type", after: 1.6)
            core.palette.query = query
            await step("close", after: 2.4)
            core.paletteCoordinator.hidePalette()
            await step("quit", after: 1.6)
            NSApp.terminate(nil)
        }
    }

    private static var backdrop: NSWindow?

    /// A light wallpaper and menu bar under the island, over the recorded area only, so its black reads on any
    /// desktop and nothing behind it is recorded. It never takes the pointer or key.
    private static func wallpaper(on screen: NSScreen) -> NSWindow {
        let frame = CGRect(x: screen.frame.midX - 500, y: screen.frame.maxY - 600, width: 1000, height: 600)
        let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        // The island's own level, ordered behind this app's island: another island app at that level stays under it.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = NSImageView(image: NSImage(size: frame.size, flipped: false) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.80, green: 0.85, blue: 0.91, alpha: 1),
                                NSColor(srgbRed: 0.93, green: 0.90, blue: 0.86, alpha: 1)])?.draw(in: rect, angle: -70)
            NSColor.white.withAlphaComponent(0.55).setFill()
            CGRect(x: 0, y: rect.maxY - menuBar, width: rect.width, height: menuBar).fill()
            return true
        })
        window.orderFrontRegardless()
        for island in NSApp.windows where island is IslandPanel && island.isVisible { island.orderFrontRegardless() }
        return window
    }

    /// A MacBook-sized notch on the first screen when the demo asks for the built-in display but no screen has
    /// one (the built-in display is mirrored or closed). The island draws its black over it, as over a real notch.
    static func simulatedNotch(on screen: NSScreen) -> CGRect? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NOTCHCAST_LIVE_DEMO"] != nil, environment["NOTCHCAST_LIVE_DEMO_SCREEN"] != "external",
              !NSScreen.screens.contains(where: { $0.safeAreaInsets.top > 0 }),
              screen == NSScreen.screens.first else { return nil }
        let frame = screen.frame
        return CGRect(x: frame.midX - 92, y: frame.maxY - 32, width: 184, height: 32)
    }

    private static let artwork = NSImage(size: CGSize(width: 64, height: 64), flipped: false) { rect in
        NSGradient(colors: [.systemIndigo, .systemPink])?.draw(in: rect, angle: 45)
        return true
    }
}
#endif
