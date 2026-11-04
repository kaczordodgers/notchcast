#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum NotchcastGallery {
    static func bootIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["NOTCHCAST_GALLERY"] != nil else { return false }
        let environment = ProcessInfo.processInfo.environment
        guard let home = environment["CFFIXED_USER_HOME"],
              home == environment["HOME"],
              home != getpwuid(getuid()).map({ String(cString: $0.pointee.pw_dir) }),
              URL(filePath: NSHomeDirectory()).standardizedFileURL == URL(filePath: home).standardizedFileURL,
              FileManager.default.fileExists(atPath: home + "/.notchcast-gallery-home") else {
            print("gallery: refused: a marked disposable HOME and CFFIXED_USER_HOME are required")
            exit(2)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(environment["NOTCHCAST_SETTINGS_ONSCREEN"] == "1" ? .accessory : .prohibited)
        UserDefaults.standard.setVolatileDomain([
            "showInMenuBar": false, "calendarEnabled": false, "automaticallyCheckForUpdates": false,
            "AppleLanguages": ["en"], "NSQuitAlwaysKeepsWindows": false
        ], forName: UserDefaults.argumentDomain)
        Motion.isEnabled = false
        _ = runIfRequested(AppCore.shared)
        application.run()
        return true
    }

    static func runIfRequested(_ core: AppCore) -> Bool {
        if GallerySettingsTiming.runIfRequested(core) { return true }
        guard let directory = ProcessInfo.processInfo.environment["NOTCHCAST_GALLERY"] else { return false }
        Task { @MainActor in
            do {
                let output = URL(filePath: directory, directoryHint: .isDirectory)
                let pages = GalleryPages.island(core) + GalleryPages.launcher(core)
                    + GalleryPages.notchcastSettings(core) + GalleryPages.settings(core)
                guard !pages.isEmpty, Set(pages.map(\.name)).count == pages.count else {
                    throw GalleryFailure.invalidRegistry
                }
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                try (pages.map { $0.name + ".png" }.joined(separator: "\n") + "\n")
                    .write(to: output.appending(path: "manifest.txt"), atomically: false, encoding: .utf8)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(pages.map { GalleryCoverage(page: $0.name, types: $0.types) })
                    .write(to: output.appending(path: "coverage.json"))
                for page in pages {
                    try Task.checkCancellation()
                    FileHandle.standardOutput.write(Data("gallery: rendering \(page.name)\n".utf8))
                    let window = page.makeWindow()
                    defer { window.close() }
                    try await Task.sleep(for: .milliseconds(160))
                    window.contentView?.layoutSubtreeIfNeeded()
                    page.prepare(window)
                    try await Task.sleep(for: page.settle)
                    page.finish()
                    try GalleryCapture.write(page: page, window: window, output: output)
                    print("gallery: wrote \(page.name)")
                }
                print("gallery: PASS \(pages.count) pages")
                exit(0)
            } catch {
                print("gallery: FAIL \(error)")
                exit(1)
            }
        }
        return true
    }
}

enum GalleryFailure: Error {
    case invalidRegistry
    case capture(String)
}

struct GalleryCoverage: Encodable {
    let page: String
    let types: [String]
}

@MainActor
struct GalleryPage {
    let name: String
    let types: [String]
    var hardwareNotch: CGRect?
    var silhouette: ((NSWindow) -> CGPath)?
    let makeWindow: () -> NSWindow
    var prepare: (NSWindow) -> Void = { _ in }
    var settle: Duration = .milliseconds(160)
    var finish: () -> Void = {}
}

@MainActor
enum GalleryPages {
    static func window(_ view: some View, size: CGSize, dark: Bool) -> NSWindow {
        let window = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.hasShadow = false
        window.backgroundColor = .windowBackgroundColor
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        hosting.sizingOptions = []
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        return window
    }
}
#endif
