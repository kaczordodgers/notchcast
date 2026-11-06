// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/ScreenshotModule*.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/Model/ScreenshotRequest.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/*.swift
// notchcast-sources: Tinycast/Platform/ScreenTarget.swift
import AppKit

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature?
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

@MainActor enum NotchcastCore {
    static let captureEditor = EditorProbe()
    static var instance: ScreenshotModule?
    static var screenshot: ScreenshotModule { instance! }
}

@MainActor final class EditorProbe {
    var opens = 0
    var failure: (any Error)?
    func openCapture(url: URL?, clipboard: Bool) throws {
        opens += 1
        if let failure { throw failure }
    }
}

@MainActor final class AppCore {
    enum Tone { case danger }
    static let shared = AppCore()
    var messages: [String] = []
    func showMessage(_ message: String, tone: Tone) { messages.append(message) }
}

@MainActor enum ScreenshotService {
    static func capture(
        _ request: ScreenshotRequest, destination: ScreenshotRequest.Destination,
        isEnabled: @MainActor () -> Bool
    ) async throws -> URL? { preconditionFailure("Harness must inject capture") }
}

@main struct CaptureScreenshotAreaTest {
    @MainActor static func main() async throws {
        let suite = "screenshot-area-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var starts = 0
        var next: CaptureAreaSelection?
        let area = CaptureAreaService(hasScreenRecordingAccess: { true }, select: {
            starts += 1
            $0(next)
        })
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Untouched", forType: .string)
        var captures: [CGRect] = []
        var files = 0
        let module = ScreenshotModule(defaults: defaults, area: area, capture: { request, destination, valid in
            precondition(valid())
            guard case .rect(let rect) = request else { preconditionFailure("Expected rect") }
            captures.append(rect)
            switch destination {
            case .clipboard: board.clearContents(); board.setString("Captured", forType: .string)
            case .file: files += 1
            case .both: preconditionFailure("Unexpected destination")
            }
            return nil
        })
        NotchcastCore.instance = module
        defer { module.stop(); NotchcastCore.instance = nil }
        let command = ScreenshotModule.areaCommand
        precondition(command.slug == "screenshot-area" && command.feature == .screenshot)
        command.run()
        precondition(starts == 0)
        module.start()
        let wasOn = NotchcastPreferences.shared.isOn(.captureEditor)
        NotchcastPreferences.shared.set(.captureEditor, false)
        defer { NotchcastPreferences.shared.set(.captureEditor, wasOn) }
        for (frame, start, end, expected) in [
            (CGRect(x: 0, y: 0, width: 1440, height: 900), CGPoint(x: 10, y: 20),
             CGPoint(x: 110, y: 70), CGRect(x: 10, y: 830, width: 100, height: 50)),
            (CGRect(x: -1920, y: 200, width: 1920, height: 1080), CGPoint(x: -1800, y: 300),
             CGPoint(x: -1500, y: 500), CGRect(x: -1800, y: 400, width: 300, height: 200))
        ] {
            let selection = CaptureAreaSelection.make(from: start, to: end, displayID: 2,
                displayFrame: frame, mainDisplayHeight: 900)!
            precondition(selection.rect == expected)
            next = selection
            command.run()
            await module.commandTask?.value
            precondition(captures.last == expected)
        }
        precondition(starts == 2 && captures.count == 2)
        precondition(NotchcastCore.captureEditor.opens == 0)
        NotchcastPreferences.shared.set(.captureEditor, true)
        NotchcastCore.captureEditor.failure = CocoaError(.fileReadCorruptFile)
        command.run()
        await module.commandTask?.value
        precondition(NotchcastCore.captureEditor.opens == 1)
        precondition(AppCore.shared.messages == [CocoaError(.fileReadCorruptFile).localizedDescription])
        AppCore.shared.messages.removeAll()
        NotchcastPreferences.shared.set(.captureEditor, false)
        precondition(board.string(forType: .string) == "Captured")
        let changes = board.changeCount
        next = nil
        command.run()
        await module.commandTask?.value
        precondition(captures.count == 3 && board.changeCount == changes)
        module.destination = .file
        next = .init(rect: CGRect(x: 1, y: 2, width: 3, height: 4), displayID: 1, displayFrame: .zero)
        command.run()
        await module.commandTask?.value
        precondition(files == 1 && board.changeCount == changes)
        module.stop()
        command.run()
        precondition(captures.count == 4 && AppCore.shared.messages.isEmpty)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try String(contentsOf: root.appendingPathComponent(
            "Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog+All.swift"), encoding: .utf8)
        precondition(catalog.contains("ScreenshotModule.areaCommand,"))
        print("PASS: area command selection; primary and offset Quartz rects; cancel preserves clipboard; destination and stop")
    }
}
