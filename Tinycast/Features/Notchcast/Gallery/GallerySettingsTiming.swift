#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum GallerySettingsTiming {
    struct Measurement: Encodable {
        let slug: String
        let appearance: String
        let source: String
        let openMilliseconds: [Double]
        let switchMilliseconds: [Double]
        var onscreen: Bool? = nil
        var screenRefreshRate: Double? = nil
        var openMedian: Double { openMilliseconds.sorted()[openMilliseconds.count / 2] }
        var switchMedian: Double { switchMilliseconds.sorted()[switchMilliseconds.count / 2] }

        enum CodingKeys: String, CodingKey {
            case slug, appearance, source, openMilliseconds, switchMilliseconds, openMedian, switchMedian
            case onscreen, screenRefreshRate
        }

        func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(slug, forKey: .slug)
            try values.encode(appearance, forKey: .appearance)
            try values.encode(source, forKey: .source)
            try values.encode(openMilliseconds, forKey: .openMilliseconds)
            try values.encode(switchMilliseconds, forKey: .switchMilliseconds)
            try values.encode(openMedian, forKey: .openMedian)
            try values.encode(switchMedian, forKey: .switchMedian)
            try values.encodeIfPresent(onscreen, forKey: .onscreen)
            try values.encodeIfPresent(screenRefreshRate, forKey: .screenRefreshRate)
        }
    }

    static func runIfRequested(_ core: AppCore) -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard environment["NOTCHCAST_GALLERY_SETTINGS"] != nil,
              let directory = environment["NOTCHCAST_GALLERY"] else { return false }
        Task { @MainActor in
            do {
                let slugs = (environment["NOTCHCAST_SETTINGS_TABS"] ?? "notchcast").split(separator: ",").map(String.init)
                let tabs = slugs.compactMap(SettingsTab.init(slug:))
                guard !tabs.isEmpty, tabs.count == slugs.count, Set(slugs).count == slugs.count else {
                    throw GalleryFailure.invalidRegistry
                }
                let trials = max(1, Int(environment["NOTCHCAST_SETTINGS_TRIALS"] ?? "") ?? 5)
                if environment["NOTCHCAST_SETTINGS_ALL_ON"] != nil {
                    for feature in NotchcastFeature.allCases where feature.isWired {
                        NotchcastPreferences.shared.set(feature, true)
                    }
                }
                let output = URL(filePath: directory, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                var results: [Measurement] = []
                if environment["NOTCHCAST_SETTINGS_ONSCREEN"] == "1" {
                    results = try await GallerySettingsOnscreenTiming.measure(core, tabs: tabs, trials: trials)
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(results).write(to: output.appending(path: "timings.json"))
                    exit(0)
                }
                for tab in tabs {
                    for dark in [false, true] {
                        let source: SettingsTab = tab == .general ? .about : .general
                        var opens: [Double] = []
                        var switches: [Double] = []
                        for trial in 0..<trials {
                            FileHandle.standardError.write(Data("start \(tab.slug) \(dark) \(trial)\n".utf8))
                            let navigation = SettingsNavigationState(tab: tab)
                            let presenter = SettingsEditorPresenter(core: core, navigation: navigation)
                            let start = CACurrentMediaTime()
                            let window = GalleryPages.window(
                                SettingsDetailView().settingsEnvironment(
                                    core: core, navigation: navigation, editorPresenter: presenter),
                                size: CGSize(width: 800, height: 800), dark: dark)
                            try await display(window)
                            opens.append((CACurrentMediaTime() - start) * 1000)
                            navigation.select(source)
                            try await display(window)
                            let switchStart = CACurrentMediaTime()
                            navigation.select(tab)
                            try await display(window)
                            switches.append((CACurrentMediaTime() - switchStart) * 1000)
                            let line = String(format: "trial %@ %@ %d open %.1f switch %.1f\n", tab.slug,
                                              dark ? "dark" : "light", trial, opens[trial], switches[trial])
                            FileHandle.standardError.write(Data(line.utf8))
                            if trial == trials - 1 {
                                try await fitContent(window)
                                let page = GalleryPage(name: "\(tab.slug)-\(dark ? "dark" : "light")",
                                                       types: ["SettingsDetailView"], makeWindow: { window })
                                try GalleryCapture.write(page: page, window: window, output: output)
                            }
                            window.close()
                        }
                        results.append(Measurement(slug: tab.slug, appearance: dark ? "dark" : "light",
                                                   source: source.slug, openMilliseconds: opens,
                                                   switchMilliseconds: switches))
                    }
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(results).write(to: output.appending(path: "timings.json"))
                try results.map { "\($0.slug)-\($0.appearance).png" }.joined(separator: "\n")
                    .write(to: output.appending(path: "manifest.txt"), atomically: false, encoding: .utf8)
                print("Tab Appearance Open median (ms) Switch median (ms); n=\(trials)")
                for result in results {
                    print(String(format: "%@ %@ %.2f %.2f", result.slug, result.appearance,
                                 result.openMedian, result.switchMedian))
                }
                exit(0)
            } catch {
                print("settings timing: FAIL \(error)")
                exit(1)
            }
        }
        return true
    }

    static func display(_ window: NSWindow) async throws {
        await Task.yield()
        try Task.checkCancellation()
        guard !window.isVisible, let content = window.contentView else {
            throw GalleryFailure.capture("timing display")
        }
        let view = content.superview ?? content
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw GalleryFailure.capture("timing bitmap")
        }
        window.appearance?.performAsCurrentDrawingAppearance {
            view.layoutSubtreeIfNeeded()
            view.cacheDisplay(in: content.bounds, to: bitmap)
        }
    }

    static func fitContent(_ window: NSWindow) async throws {
        try await Task.sleep(for: .milliseconds(160))
        func height(_ view: NSView) -> CGFloat {
            let documentHeight = (view as? NSScrollView)?.documentView?.frame.height ?? 0
            return max(documentHeight, view.subviews.map(height).max() ?? 0)
        }
        for _ in 0..<4 {
            guard let view = window.contentView else { throw GalleryFailure.capture("missing host") }
            let required = max(800, ceil(height(view)))
            if abs(required - view.bounds.height) < 1 { break }
            window.setContentSize(CGSize(width: 800, height: required))
            try await display(window)
        }
    }
}
#endif
