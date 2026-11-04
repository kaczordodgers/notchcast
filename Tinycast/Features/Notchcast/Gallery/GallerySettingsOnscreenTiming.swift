#if DEBUG
import AppKit
import QuartzCore

@MainActor
enum GallerySettingsOnscreenTiming {
    static func measure(_ core: AppCore, tabs: [SettingsTab], trials: Int) async throws
        -> [GallerySettingsTiming.Measurement] {
        let coordinator = SettingsCoordinator(core: core)
        defer { coordinator.closeSettings() }
        var results: [GallerySettingsTiming.Measurement] = []
        for tab in tabs {
            for dark in [false, true] {
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let source: SettingsTab = tab == .general ? .about : .general
                var opens: [Double] = []
                var switches: [Double] = []
                var refreshRate = 0.0
                for trial in 0..<trials {
                    coordinator.closeSettings()
                    progress("start \(tab.slug) \(dark ? "dark" : "light") \(trial + 1)")
                    let existing = Set(NSApp.windows.map(ObjectIdentifier.init))
                    let start = CACurrentMediaTime()
                    coordinator.showSettings(tab: tab)
                    guard let window = NSApp.windows.first(where: {
                        $0.isVisible && !existing.contains(ObjectIdentifier($0))
                    }), let screen = window.screen else {
                        throw GalleryFailure.capture("onscreen Settings window missing")
                    }
                    let frame = FrameSignal()
                    try await frame.commit(window)
                    opens.append((CACurrentMediaTime() - start) * 1000)
                    refreshRate = frame.refreshRate
                    guard window.screen === screen else {
                        throw GalleryFailure.capture("Settings screen changed")
                    }
                    coordinator.showSettings(tab: source)
                    try await frame.commit(window)
                    let switchStart = CACurrentMediaTime()
                    coordinator.showSettings(tab: tab)
                    try await frame.commit(window)
                    switches.append((CACurrentMediaTime() - switchStart) * 1000)
                    coordinator.closeSettings()
                    progress(String(format: "trial %@ %@ %d open %.2f switch %.2f Hz %.2f", tab.slug,
                                    dark ? "dark" : "light", trial + 1, opens[trial], switches[trial], refreshRate))
                }
                results.append(.init(slug: tab.slug, appearance: dark ? "dark" : "light", source: source.slug,
                                     openMilliseconds: opens, switchMilliseconds: switches,
                                     onscreen: true, screenRefreshRate: refreshRate))
            }
        }
        return results
    }

    private static func progress(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    @MainActor private final class FrameSignal: NSObject {
        private var continuation: CheckedContinuation<Void, any Error>?
        private(set) var refreshRate = 0.0

        func commit(_ window: NSWindow) async throws {
            await Task.yield()
            try Task.checkCancellation()
            guard window.isVisible, let content = window.contentView else {
                throw GalleryFailure.capture("Settings closed during timing")
            }
            let view = content.superview ?? content
            view.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            let link = window.displayLink(target: self, selector: #selector(tick))
            let timeout = Timer(timeInterval: 5, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    let pending = self?.continuation
                    self?.continuation = nil
                    pending?.resume(throwing: GalleryFailure.capture("display-link timeout"))
                }
            }
            defer {
                link.invalidate()
                timeout.invalidate()
            }
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                RunLoop.main.add(timeout, forMode: .common)
                link.add(to: .main, forMode: .common)
            }
            try Task.checkCancellation()
            guard window.isVisible else { throw GalleryFailure.capture("Settings closed before refresh") }
        }

        @objc private func tick(_ link: CADisplayLink) {
            let interval = link.targetTimestamp - link.timestamp
            if interval > 0 { refreshRate = 1 / interval }
            let pending = continuation
            continuation = nil
            pending?.resume()
        }
    }
}
#endif
