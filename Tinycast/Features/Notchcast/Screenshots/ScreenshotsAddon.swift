// notchcast-addon-order: 90
// notchcast-readme: Capture: screenshots of an area, window or display,
// notchcast-readme: Capture: an editor to mark one up with arrows, shapes, highlights, text, pixelation and a crop before copying, saving or dragging it out,
// notchcast-readme: Capture: and a scrolling capture that joins a long page into one tall image
import SwiftUI

/// Area, window, display and scrolling screenshots, and their text, from one frozen selection surface.
enum ScreenshotsAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "screenshot",
            title: String(localized: "Screenshots", table: "NotchcastScreenshots"),
            subtitle: String(localized: "Capture an area, window or display, or copy its text.", table: "NotchcastScreenshots"),
            category: .capture,
            defaultEnabled: true,
            requiredGrants: [.screenRecording]
        ),
    ]

    static let commands = [
        NotchcastCommand(
            slug: "screenshot-area", name: String(localized: "Capture Area", table: "NotchcastScreenshots"),
            symbol: "camera.viewfinder", switchID: ScreenshotsModule.switchID
        ) { $0.module(ScreenshotsModule.self)?.captureArea() },
        NotchcastCommand(
            slug: "screenshot-display", name: String(localized: "Capture Screen", table: "NotchcastScreenshots"),
            symbol: "camera", switchID: ScreenshotsModule.switchID
        ) { $0.module(ScreenshotsModule.self)?.captureDisplay() },
        NotchcastCommand(
            slug: "edit-last-screenshot", name: String(localized: "Edit Last Screenshot", table: "NotchcastScreenshots"),
            symbol: "pencil.tip.crop.circle", switchID: ScreenshotsModule.switchID,
            keywords: ["annotate", "markup", "capture editor"]
        ) { $0.module(ScreenshotsModule.self)?.editLastCapture() },
        NotchcastCommand(
            slug: "capture-text", name: String(localized: "Capture Text", table: "NotchcastScreenshots"),
            symbol: ScreenshotsModule.textSymbol, switchID: ScreenshotsModule.switchID,
            keywords: ["ocr", "copy text", "recognize"]
        ) { $0.module(ScreenshotsModule.self)?.captureText() },
        NotchcastCommand(
            slug: "scrolling-capture", name: String(localized: "Scrolling Capture", table: "NotchcastScreenshots"),
            symbol: "arrow.up.and.down.square", switchID: ScreenshotsModule.switchID,
            keywords: ["long screenshot", "full page", "scroll", "stitch"]
        ) { $0.module(ScreenshotsModule.self)?.captureScrolling() },
    ]

    static let settings = [
        NotchcastSettingsRow(switchID: ScreenshotsModule.switchID) {
            AnyView(ScreenshotsSettingsView(defaults: $0.defaults))
        },
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        ScreenshotsModule(context: context, system: .live)
    }
}
