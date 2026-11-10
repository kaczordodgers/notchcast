// notchcast-sources: Tinycast/Features/CaptureScreenshot/ScreenshotModule+Command.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/Model/ScreenshotRequest.swift
// notchcast-sources: Tinycast/Features/ColorPicker/ColorPickerModule+Command.swift
// notchcast-sources: Tinycast/Platform/ScreenTarget.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/*.swift
// notchcast-kit: command
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
import AppKit

@MainActor final class ScreenshotModule {
    enum Destination { case clipboard, file }
    let destination = Destination.clipboard
    let enabled = true
    let area = CaptureAreaService(hasScreenRecordingAccess: { true }, select: {
        $0(.init(rect: CGRect(x: 0, y: 0, width: 20, height: 20), displayID: 1, displayFrame: .zero))
    })
    var captures = 0
    var commandTask: Task<Void, Never>?
    static func failureMessage(_ error: any Error) -> String { error.localizedDescription }
    func capture(_ request: ScreenshotRequest) async throws -> URL? { captures += 1; return nil }
}

@MainActor final class ColorPickerModule {
    var outcome = ColorPickerService.Outcome.copyFailed
    func pick(completion: (ColorPickerService.Outcome) -> Void) { completion(outcome) }
}

enum ColorPickerService {
    enum Outcome { case copied, copyFailed, cancelled }
}

@MainActor enum NotchcastCore {
    static let captureEditor = CaptureEditorProbe()
    static let screenshot = ScreenshotModule()
    static let colorPicker = ColorPickerModule()
}

@MainActor final class CaptureEditorProbe {
    enum Failure: LocalizedError {
        case noImage
        var errorDescription: String? { "No Image to Edit" }
    }
    func openCapture(url: URL?, clipboard: Bool) throws { throw Failure.noImage }
}

enum NotchcastFeature { case screenshot, colorPicker, captureEditor }

@MainActor final class AppCore {
    enum Tone { case danger }
    static let shared = AppCore()
    var messages: [String] = []
    func showMessage(_ message: String, tone: Tone) { messages.append(message) }
}

@main @MainActor struct CaptureErrorsTest {
    static func main() async {
        NotchcastCore.screenshot.captureArea()
        await NotchcastCore.screenshot.commandTask?.value
        precondition(NotchcastCore.screenshot.captures == 1)
        precondition(AppCore.shared.messages == ["No Image to Edit"])
        AppCore.shared.messages.removeAll()
        ColorPickerModule.launcherCommand.run()
        precondition(AppCore.shared.messages == [String(localized: "Pick Color")])
        NotchcastCore.colorPicker.outcome = .copied
        ColorPickerModule.launcherCommand.run()
        precondition(AppCore.shared.messages.count == 1)
        NotchcastCore.colorPicker.outcome = .cancelled
        ColorPickerModule.launcherCommand.run()
        precondition(AppCore.shared.messages.count == 1)
        print("PASS: screenshot area error HUD; color copy failure and success")
    }
}
