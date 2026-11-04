// notchcast-sources: -target arm64-apple-macos26.0 Tinycast/Features/CaptureRecording/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingModule.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingCommands.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingFiles.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingWriting.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingSource.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift Tinycast/Features/CaptureArea/Service/*.swift
// notchcast-sources: Tinycast/Platform/ScreenTarget.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
import AppKit
import CoreMedia

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    var feature: NotchcastFeature?
    var owner: SettingsTab? = .notchcast
    var legacyID: String?
    var isEnabled: @MainActor @Sendable () -> Bool = { true }
    let run: @MainActor @Sendable () -> Void
}

enum SettingsTab { case notchcast }

@MainActor final class AppCore {
    enum Tone { case danger, neutral }
    static let shared = AppCore()
    var messages: [(String, Tone)] = []
    func showMessage(_ text: String, tone: Tone) { messages.append((text, tone)) }
}

@MainActor enum NotchcastCore {
    static var recording = RecordingModule()
}

@main struct RecordingCommandTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "recording-commands-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = ScreenRecordingSource()
        var selection: CaptureAreaSelection?
        let area = CaptureAreaService(hasScreenRecordingAccess: { true }, select: { $0(selection) })
        let module = RecordingModule(defaults: defaults, defaultFolder: root, commandArea: area,
                                     makeSource: { source }, sleep: {})
        NotchcastCore.recording = module
        let preferences = NotchcastPreferences.shared
        let previous = preferences.isOn(.recording)
        defer { preferences.set(.recording, previous) }
        preferences.set(.recording, false)
        let commands = [RecordingCommands.screen, RecordingCommands.area, RecordingCommands.pause, RecordingCommands.stop]
        precondition(commands.allSatisfy { !$0.isEnabled() })
        preferences.set(.recording, true)
        precondition(!RecordingCommands.pause.isEnabled() && !RecordingCommands.stop.isEnabled())
        var failures: [String] = []
        await module.executeRecordingCommand(.record(.display(1)), report: { if $1 { failures.append($0) } })
        precondition(failures == [RecordingTarget.Failure.disabled.localizedDescription])
        module.start()
        RecordingCommands.screen.run()
        await module.commandTask?.value
        guard case .display = source.target else { preconditionFailure("screen target") }
        precondition(RecordingCommands.pause.isEnabled() && RecordingCommands.stop.isEnabled())
        await module.executeRecordingCommand(.record(.display(2)), report: { if $1 { failures.append($0) } })
        precondition(failures.last == RecordingTarget.Failure.busy.localizedDescription)
        RecordingCommands.pause.run()
        await module.commandTask?.value
        precondition(module.phase == .paused)
        RecordingCommands.pause.run()
        await module.commandTask?.value
        precondition(module.phase == .recording)
        var revealed: URL?
        var success = false
        await module.executeRecordingCommand(.finish,
            report: { success = $0 == "Recording saved" && !$1 }, reveal: { revealed = $0 })
        precondition(success && revealed != nil && FileManager.default.fileExists(atPath: revealed!.path))
        precondition(module.phase == .idle && !RecordingCommands.stop.isEnabled())
        RecordingCommands.stop.run()
        await module.commandTask?.value
        precondition(AppCore.shared.messages.last?.0 == RecordingTarget.Failure.notRecording.localizedDescription)
        precondition(AppCore.shared.messages.last?.1 == .danger)
        let count = source.starts
        RecordingCommands.area.run()
        precondition(source.starts == count && module.phase == .idle)
        selection = CaptureAreaSelection(rect: CGRect(x: 10, y: 20, width: 40, height: 50), displayID: 1, displayFrame: .zero)
        RecordingCommands.area.run()
        await module.commandTask?.value
        precondition(source.target == .area(selection!.rect))
        module.stop()
        await module.waitUntilIdle()
        module.start()
        source.denied = true
        await module.executeRecordingCommand(.record(.display(1)), report: { if $1 { failures.append($0) } })
        precondition(failures.last == RecordingTarget.Failure.permissionDenied.localizedDescription)
        print("PASS screen/area targets, cancelled selection, pause/resume, published URL reveal")
        print("PASS disabled/busy/permission danger failures, switch and idle availability")
    }
}

@MainActor final class ScreenRecordingSource: RecordingSource {
    var target: RecordingTarget?
    var starts = 0
    var denied = false
    func prepare(_ target: RecordingTarget, frameRate: Int) async throws -> RecordingFormat {
        if denied { throw RecordingTarget.Failure.permissionDenied }
        self.target = target
        return RecordingFormat(width: 64, height: 64, frameRate: frameRate)
    }
    func start(writer: any RecordingWriting, onFailure: @escaping @MainActor (any Error) -> Void) async throws {
        starts += 1
        writer.begin(at: .zero)
    }
    func stop() async throws {}
}

final class RecordingWriter: RecordingWriting {
    let url: URL
    init(url: URL) { self.url = url }
    static func create(url: URL, format: RecordingFormat) async throws -> RecordingWriter { RecordingWriter(url: url) }
    func begin(at time: CMTime) {}
    func append(_ sample: CMSampleBuffer, track: RecordingFormat.Track) throws {}
    func setPaused(_ paused: Bool, at time: CMTime) {}
    func finish(at time: CMTime) async throws { try Data("fake recording".utf8).write(to: url) }
    func cancel() async {}
}
