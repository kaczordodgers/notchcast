// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/CaptureScrolling/ScrollingCaptureModule*.swift
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
    static var module: ScrollingCaptureModule?
    static var scrollingCapture: ScrollingCaptureModule { module! }
}
@MainActor final class AppCore {
    enum Tone { case neutral, danger }
    static let shared = AppCore()
    var messages: [String] = []
    var tones: [Tone] = []
    func showMessage(_ text: String, tone: Tone) { messages.append(text); tones.append(tone) }
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
@MainActor final class ScrollingCaptureSession {
    enum State { case idle, capturing, limitReached }
    enum Failure: Error { case permissionDenied, invalidRect, displayUnavailable }
    var state = State.idle
    var starts = 0
    var stops = 0
    var cancels = 0
    func start(rect: CGRect, displayID: UInt32) throws { starts += 1; state = .capturing }
    func cancel() { cancels += 1; state = .idle }
    func stop() async throws -> Data? { stops += 1; state = .idle; return Data([1, 2, 3]) }
    static func pngData(for image: Data) async throws -> Data { image }
}
@main @MainActor struct ScrollingModuleTest {
    static func main() async throws {
        let area = CaptureAreaService()
        let session = ScrollingCaptureSession()
        var output: [Data] = []
        let module = ScrollingCaptureModule(area: area, session: session, write: { output.append($0); return true })
        NotchcastCore.module = module
        let preferences = NotchcastPreferences.shared
        let controller = NotchcastModuleController(
            [.init(requires: [.scrollingCapture], module: module)], preferences: preferences)
        controller.run()
        let command = ScrollingCaptureModule.launcherCommand
        precondition(!command.isEnabled())
        command.run()
        precondition(area.starts == 0)
        preferences.set(.scrollingCapture, true)
        for _ in 0..<100 { await Task.yield() }
        precondition(command.isEnabled())
        command.run()
        precondition(session.starts == 1 && session.state == .capturing)
        precondition(AppCore.shared.tones == [.neutral])
        command.run()
        for _ in 0..<100 { await Task.yield() }
        precondition(session.stops == 1 && output == [Data([1, 2, 3])])
        area.denied = true
        command.run()
        precondition(AppCore.shared.messages.last == String(localized: "Screen Recording access is required."))
        precondition(AppCore.shared.tones.last == .danger)
        preferences.set(.scrollingCapture, false)
        for _ in 0..<100 { await Task.yield() }
        precondition(session.cancels == 1 && area.stops == 1 && !command.isEnabled())
        command.run()
        precondition(area.starts == 2)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let section = try String(contentsOf: root.appendingPathComponent(
            "Tinycast/Features/CaptureScrolling/ScrollingCaptureSettingsSection.swift"), encoding: .utf8)
        precondition(section.contains("preferences.set(.scrollingCapture, $0)"))
        print("PASS: scrolling lifecycle, command output, permission HUD, settings switch")
    }
}
