// notchcast-sources: Tinycast/Features/CaptureScreenshot/ScreenshotModule+Command.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/Model/ScreenshotRequest.swift
// notchcast-sources: Tinycast/Features/ColorPicker/ColorPickerModule+Command.swift
// notchcast-sources: Tinycast/Platform/ScreenTarget.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/*.swift
import AppKit

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastPreferences.Feature?
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

@MainActor final class ScreenshotModule {
    let enabled = true
    let area = CaptureAreaService()
    var commandTask: Task<Void, Never>?
    func capture(_ request: ScreenshotRequest) async throws -> URL? { nil }
}

@MainActor final class ColorPickerModule {
    var outcome = ColorPickerService.Outcome.copyFailed
    func pick(completion: (ColorPickerService.Outcome) -> Void) { completion(outcome) }
}

enum ColorPickerService {
    enum Outcome { case copied, copyFailed, cancelled }
}

@MainActor enum NotchcastCore {
    static let screenshot = ScreenshotModule()
    static let colorPicker = ColorPickerModule()
}

@MainActor final class NotchcastPreferences {
    enum Feature { case screenshot, colorPicker }
    static let shared = NotchcastPreferences()
    func isOn(_ feature: Feature) -> Bool { true }
}

@MainActor final class AppCore {
    enum Tone { case danger }
    static let shared = AppCore()
    var messages: [String] = []
    func showMessage(_ message: String, tone: Tone) { messages.append(message) }
}

@main @MainActor struct CaptureErrorsTest {
    static func main() {
        precondition(ScreenshotModule.failureMessage(ScreenshotRequest.Failure.permissionDenied)
                     == String(localized: "Screen Recording access is required."))
        precondition(ScreenshotModule.failureMessage(ScreenshotRequest.Failure.clipboardFailed)
                     == String(localized: "Could not copy to clipboard."))
        precondition(ScreenshotModule.failureMessage(NSError(domain: "com.apple.ScreenCaptureKit", code: -3802))
                     == String(localized: "Could not capture the screen."))
        precondition(ScreenshotModule.failureMessage(CocoaError(.fileWriteNoPermission))
                     == String(localized: "Could not save the screenshot."))
        ColorPickerModule.launcherCommand.run()
        precondition(AppCore.shared.messages == [String(localized: "Pick Color")])
        NotchcastCore.colorPicker.outcome = .copied
        ColorPickerModule.launcherCommand.run()
        precondition(AppCore.shared.messages.count == 1)
        NotchcastCore.colorPicker.outcome = .cancelled
        ColorPickerModule.launcherCommand.run()
        precondition(AppCore.shared.messages.count == 1)
        print("PASS: screenshot permission, clipboard, capture and save errors; color copy failure and success")
    }
}
