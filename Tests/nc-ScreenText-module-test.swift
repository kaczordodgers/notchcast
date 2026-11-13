// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-kit: core host command isolated-identity
// notchcast-sources: Tinycast/Features/ScreenText/ScreenTextModule.swift
// notchcast-sources: Tinycast/Features/ScreenText/ScreenTextModule+Command.swift
// notchcast-sources: Tinycast/Features/ScreenText/Model/ScreenTextResult.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/CaptureAreaSelection.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/CaptureFailure.swift
import AppKit
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
    enum Failure: CaptureFailureConvertible {
        case clipboardWriteFailed, noContent, displayUnavailable
        var captureFailure: CaptureFailure? {
            switch self {
            case .clipboardWriteFailed: .clipboardFailed
            case .displayUnavailable: .areaUnavailable
            case .noContent: nil
            }
        }
    }
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
        defer { preferences.engineDefaults.removePersistentDomain(forName: NotchcastIdentity.current.suiteName()) }
        preferences.set(.screenText, false)
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
        precondition(messages == [String(localized: "Screen Recording access is required.")])
        let stops = area.stops
        preferences.set(.screenText, false)
        for _ in 0..<100 { await Task.yield() }
        precondition(area.stops > stops && !command.isEnabled())
        command.run()
        precondition(area.starts == 2)
        let writeFailure = ScreenTextModule(defaults: defaults, area: CaptureAreaService(), recognize: { _, _ in
            ScreenTextResult(content: "Cannot copy", kind: .text)
        }, write: { _ in false })
        writeFailure.start()
        var writeMessages: [String] = []
        writeFailure.capture { writeMessages.append($0) }
        for _ in 0..<100 { await Task.yield() }
        precondition(writeMessages == [CaptureFailure.clipboardFailed.message])
        writeFailure.stop()
        print("PASS: OCR switch lifecycle, command recognition/output, permission HUD")
    }
}
