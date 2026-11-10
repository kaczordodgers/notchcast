// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-sources: Tinycast/Features/ScreenText/ScreenTextModule.swift
// notchcast-sources: Tinycast/Features/ScreenText/ScreenTextModule+Command.swift
// notchcast-sources: Tinycast/Features/ScreenText/Model/ScreenTextResult.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/CaptureAreaSelection.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/CaptureFailure.swift
// notchcast-reads: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettingsModule+Groups.swift
// notchcast-reads: Tinycast/Features/Notchcast/Settings/Rows/CaptureSettingRows.swift
// notchcast-reads: Tinycast/Features/Notchcast/Core/NotchcastCore+Registrants.swift
// notchcast-reads: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog+All.swift
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
extension ScreenTextModule {
    static var instance: ScreenTextModule?
    static var shared: ScreenTextModule { instance! }
}
enum DialogTone { case danger }
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
        var messages: [String] = []
        NotchcastHost.current.showMessage = { text, _ in messages.append(text) }
        let suite = "screen-text-module-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let area = CaptureAreaService()
        var output: [String] = []
        let module = ScreenTextModule(defaults: defaults, area: area, recognize: { _, _ in
            ScreenTextResult(content: "Recognized fixture", kind: .text)
        }, write: { output.append($0); return true })
        ScreenTextModule.instance = module
        let preferences = NotchcastPreferences.shared
        let controller = NotchcastModuleController(
            [.init(requires: [.screenText], module: module)], preferences: preferences)
        controller.run()
        let command = ScreenTextModule.launcherCommand
        precondition(command.id == "command:nc-screen-text" && !command.isEnabled())
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
        precondition(messages ==[String(localized: "Screen Recording access is required.")])
        let stops = area.stops
        preferences.set(.screenText, false)
        for _ in 0..<100 { await Task.yield() }
        precondition(area.stops > stops && !command.isEnabled())
        command.run()
        precondition(area.starts == 2)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for (path, needle) in [
            ("Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettingsModule+Groups.swift",
             ".feature(.screenText, settings: [.captureScreenTextLineBreaks])"),
            ("Tinycast/Features/Notchcast/Settings/Rows/CaptureSettingRows.swift",
             "Remove line breaks"),
            ("Tinycast/Features/Notchcast/Core/NotchcastCore+Registrants.swift", "ScreenTextModule.self,"),
            ("Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog+All.swift", "ScreenTextModule.launcherCommand")
        ] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            precondition(source.contains(needle), path)
        }
        print("PASS: OCR switch lifecycle, command recognition/output, permission HUD, settings and catalogue reachability")
    }
}
