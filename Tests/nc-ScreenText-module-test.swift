// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/ScreenText/ScreenTextModule*.swift
// notchcast-sources: Tinycast/Features/ScreenText/Model/ScreenTextResult.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/CaptureAreaSelection.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/CaptureFailure.swift
import AppKit
import Observation

@MainActor @Observable final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    private var enabled = false
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled }
    func set(_ feature: NotchcastFeature, _ value: Bool) { enabled = value }
}
struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature?
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
    var id: String { "command:nc-" + slug }
}
@MainActor enum NotchcastCore {
    static var module: ScreenTextModule?
    static var screenText: ScreenTextModule { module! }
}
@MainActor final class AppCore {
    enum Tone { case danger }
    static let shared = AppCore()
    var messages: [String] = []
    func showMessage(_ text: String, tone: Tone) { messages.append(text) }
}
@MainActor final class CaptureAreaService {
    var starts = 0
    var stops = 0
    var denied = false
    func start(_ select: (CaptureAreaSelection?) -> Void) throws {
        starts += 1
        if denied { throw CaptureFailure.permissionDenied }
        select(.init(rect: CGRect(x: 0, y: 0, width: 2, height: 2), displayID: 1, displayFrame: .zero))
    }
    func stop() { stops += 1 }
}
enum ScreenTextService {
    enum Failure: Error { case clipboardWriteFailed, noContent, displayUnavailable }
    static func recognize(selection: CaptureAreaSelection, removeLineBreaks: Bool) async throws -> ScreenTextResult {
        fatalError("Real recognition must not run")
    }
}
@main @MainActor struct ScreenTextModuleTest {
    static func main() async throws {
        let suite = "screen-text-module-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let area = CaptureAreaService()
        var output: [String] = []
        let module = ScreenTextModule(defaults: defaults, area: area, recognize: { _, _ in
            ScreenTextResult(content: "Recognized fixture", kind: .text)
        }, write: { output.append($0); return true })
        NotchcastCore.module = module
        let preferences = NotchcastPreferences.shared
        let controller = NotchcastModuleController(
            [.init(requires: [.screenText], module: module)], preferences: preferences)
        controller.run()
        let command = ScreenTextModule.launcherCommand
        precondition(!command.isEnabled())
        command.run()
        precondition(area.starts == 0)
        preferences.set(.screenText, true)
        for _ in 0..<100 { await Task.yield() }
        precondition(command.isEnabled())
        command.run()
        for _ in 0..<100 { await Task.yield() }
        precondition(output == ["Recognized fixture"])
        area.denied = true
        command.run()
        precondition(AppCore.shared.messages == [String(localized: "Screen Recording access is required.")])
        let stops = area.stops
        preferences.set(.screenText, false)
        for _ in 0..<100 { await Task.yield() }
        precondition(area.stops > stops && !command.isEnabled())
        command.run()
        precondition(area.starts == 2)
        print("PASS: OCR switch lifecycle, command recognition/output, permission HUD")
    }
}
