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
        var openMedian: Double { openMilliseconds.sorted()[2] }
        var switchMedian: Double { switchMilliseconds.sorted()[2] }

        enum CodingKeys: String, CodingKey {
            case slug, appearance, source, openMilliseconds, switchMilliseconds, openMedian, switchMedian
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
                let output = URL(filePath: directory, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                var results: [Measurement] = []
                for tab in tabs {
                    for dark in [false, true] {
                        let source: SettingsTab = tab == .general ? .about : .general
                        var opens: [Double] = []
                        var switches: [Double] = []
                        for trial in 0..<5 {
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
                            if trial == 4 {
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
                print("Tab Appearance Open median (ms) Switch median (ms); n=5")
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
        guard !window.isVisible, let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw GalleryFailure.capture("timing display")
        }
        window.appearance?.performAsCurrentDrawingAppearance {
            view.layoutSubtreeIfNeeded()
            view.cacheDisplay(in: view.bounds, to: bitmap)
        }
    }
}
#endif
