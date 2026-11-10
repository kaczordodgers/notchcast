// notchcast-sources: Tinycast/Features/CaptureScreenshot/ScreenshotModule+Command.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/Model/ScreenshotRequest.swift
// notchcast-sources: Tinycast/Features/ColorPicker/ColorPickerModule+Command.swift
// notchcast-sources: Tinycast/Platform/ScreenTarget.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
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
    static let shared = ScreenshotModule()
    var openInEditor: (URL?, Bool) throws -> Void = { _, _ in }
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
    static let shared = ColorPickerModule()
    var outcome = ColorPickerService.Outcome.copyFailed
    func pick(completion: (ColorPickerService.Outcome) -> Void) { completion(outcome) }
}

enum ColorPickerService {
    enum Outcome { case copied, copyFailed, cancelled }
}

@MainActor final class CaptureEditorProbe {
    enum Failure: LocalizedError {
        case noImage
        var errorDescription: String? { "No Image to Edit" }
    }
    func openCapture(url: URL?, clipboard: Bool) throws { throw Failure.noImage }
}

@MainActor final class NotchcastPreferences {
    enum Feature { case screenshot, colorPicker, captureEditor }
    static let shared = NotchcastPreferences()
    func isOn(_ feature: Feature) -> Bool { true }
}

enum DialogTone { case danger }

@main @MainActor struct CaptureErrorsTest {
    static func main() async {
        var messages: [String] = []
        NotchcastHost.current.showMessage = { text, _ in messages.append(text) }
        let editor = CaptureEditorProbe()
        ScreenshotModule.shared.openInEditor = { try editor.openCapture(url: $0, clipboard: $1) }
        ScreenshotModule.shared.captureArea()
        await ScreenshotModule.shared.commandTask?.value
        precondition(ScreenshotModule.shared.captures == 1)
        precondition(messages == ["No Image to Edit"])
        messages.removeAll()
        ColorPickerModule.launcherCommand.run()
        precondition(messages == [String(localized: "Pick Color")])
        ColorPickerModule.shared.outcome = .copied
        ColorPickerModule.launcherCommand.run()
        precondition(messages.count == 1)
        ColorPickerModule.shared.outcome = .cancelled
        ColorPickerModule.launcherCommand.run()
        precondition(messages.count == 1)
        print("PASS: screenshot area error HUD; color copy failure and success")
    }
}
