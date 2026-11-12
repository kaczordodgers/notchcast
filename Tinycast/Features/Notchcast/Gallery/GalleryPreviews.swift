#if DEBUG
import AppKit
import SwiftUI

/// Captured outside a view body, so SwiftUI inside the page still updates before the shot.
@MainActor
private func galleryPreview(_ name: String) -> some View {
    Group {
        if let page = GalleryPages.all(AppCore.shared).first(where: { $0.name == name }), let image = capture(page) {
            Image(nsImage: image)
        } else {
            Text(verbatim: "No gallery page named \(name)")
        }
    }
}

@MainActor
private func capture(_ page: GalleryPage) -> NSImage? {
    Motion.isEnabled = false
    let window = page.makeWindow()
    defer { window.close() }
    settle(window, .milliseconds(160))
    page.prepare(window)
    settle(window, page.settle)
    page.finish()
    let output = FileManager.default.temporaryDirectory.appending(path: "gallery-previews", directoryHint: .isDirectory)
    do {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try GalleryCapture.write(page: page, window: window, output: output)
    } catch { return nil }
    return NSImage(contentsOf: output.appending(path: page.name + ".png"))
}

/// The gallery sleeps; a preview cannot suspend, so it lays out and turns the run loop by hand.
@MainActor
private func settle(_ window: NSWindow, _ duration: Duration) {
    let end = Date(timeIntervalSinceNow: Double(duration.components.seconds)
        + Double(duration.components.attoseconds) / 1e18)
    repeat {
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.displayIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    } while Date() < end
}

#Preview("island-closed-timer-mba") { galleryPreview("island-closed-timer-mba") }
#Preview("island-open-home-entries-mba") { galleryPreview("island-open-home-entries-mba") }
#Preview("launcher-root-dark") { galleryPreview("launcher-root-dark") }
#Preview("settings-general-dark") { galleryPreview("settings-general-dark") }
#Preview("settings-notchcast-island-dark") { galleryPreview("settings-notchcast-island-dark") }
#Preview("launcher-root-light") { galleryPreview("launcher-root-light") }
#Preview("island-usage-dark") { galleryPreview("island-usage-dark") }
#Preview("island-usage-light") { galleryPreview("island-usage-light") }
#endif
