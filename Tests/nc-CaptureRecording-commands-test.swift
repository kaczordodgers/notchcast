// notchcast-sources: -target arm64-apple-macos26.0 Tinycast/Features/CaptureRecording/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingModule.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingCommands.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingFiles.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingWriting.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingSource.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift Tinycast/Features/CaptureArea/Service/*.swift
// notchcast-sources: Tinycast/Platform/ScreenTarget.swift
// notchcast-kit: core host
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

enum DialogTone { case danger, neutral, success }

@MainActor final class AppCore {
    static let shared = AppCore()
    var messages: [(String, DialogTone)] = []
    func showMessage(_ text: String, tone: DialogTone) { messages.append((text, tone)) }
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
        var refreshes = 0
        let module = RecordingModule(defaults: defaults, defaultFolder: root, commandArea: area,
                                     refreshCommands: { refreshes += 1 },
                                     makeSource: { source }, sleep: {})
        NotchcastCore.recording = module
        NotchcastHost.current.showMessage = { AppCore.shared.showMessage($0, tone: $1) }
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
        precondition(failures == ["Capture is disabled."])
        module.start()
        RecordingCommands.screen.run()
        await module.commandTask?.value
        guard case .display = source.target else { preconditionFailure("screen target") }
        precondition(RecordingCommands.pause.isEnabled() && RecordingCommands.stop.isEnabled())
        precondition(refreshes == 1)
        await module.executeRecordingCommand(.record(.display(2)), report: { if $1 { failures.append($0) } })
        precondition(failures.last == "A recording is already in progress.")
        RecordingCommands.pause.run()
        await module.commandTask?.value
        precondition(module.phase == .paused)
        RecordingCommands.pause.run()
        await module.commandTask?.value
        precondition(module.phase == .recording)
        precondition(refreshes == 3)
        var revealed: URL?
        var success = false
        await module.executeRecordingCommand(.finish,
            report: { success = $0 == "Recording saved" && !$1 }, reveal: { revealed = $0 })
        precondition(success && revealed != nil && FileManager.default.fileExists(atPath: revealed!.path))
        precondition(module.phase == .idle && !RecordingCommands.stop.isEnabled())
        precondition(refreshes == 4)
        RecordingCommands.stop.run()
        await module.commandTask?.value
        precondition(AppCore.shared.messages.last?.0 == "No recording is in progress.")
        precondition(AppCore.shared.messages.last?.1 == .danger)
        let count = source.starts
        RecordingCommands.area.run()
        precondition(source.starts == count && module.phase == .idle)
        selection = CaptureAreaSelection(rect: CGRect(x: 10, y: 20, width: 40, height: 50), displayID: 1, displayFrame: .zero)
        RecordingCommands.area.run()
        await module.commandTask?.value
        precondition(source.target == .area(selection!.rect))
        let publishedBefore = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }.count
        try module.setPaused(true)
        preferences.set(.recording, false)
        module.stop()
        await module.waitUntilIdle()
        let publishedAfter = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }.count
        precondition(publishedAfter == publishedBefore + 1 && !module.enabled)
        precondition(AppCore.shared.messages.last?.0 == "Recording saved")
        precondition(AppCore.shared.messages.last?.1 == .success)
        precondition(!RecordingCommands.stop.isEnabled())
        module.start()
        preferences.set(.recording, true)
        try await module.record(.display(1))
        source.holdStop = true
        preferences.set(.recording, false)
        module.stop()
        while source.stopContinuation == nil { await Task.yield() }
        module.start()
        preferences.set(.recording, true)
        source.holdStop = false
        source.stopContinuation?.resume()
        source.stopContinuation = nil
        await module.waitUntilIdle()
        precondition(module.enabled && module.phase == .idle)
        RecordingCommands.screen.run()
        await module.commandTask?.value
        precondition(module.phase == .recording)
        _ = try await module.finish()
        precondition(RecordingModule.failureMessage(NSError(domain: "start", code: 1)) == "Recording failed.")
        print("PASS off/on during held save preserves enabled state; Record Screen works; success HUD")
        source.denied = true
        await module.executeRecordingCommand(.record(.display(1)), report: { if $1 { failures.append($0) } })
        precondition(failures.last == "Screen Recording access is required.")
        precondition(RecordingModule.failureMessage(CaptureFailure.permissionDenied)
            == "Screen Recording access is required.")
        precondition(RecordingModule.failureMessage(RecordingTarget.Failure.invalidTarget) == "Capture area is unavailable.")
        precondition(RecordingModule.failureMessage(RecordingTarget.Failure.targetUnavailable) == "Capture area is unavailable.")
        precondition(RecordingModule.failureMessage(RecordingTarget.Failure.noFrames) == "The recording contains no frames.")
        precondition(RecordingModule.failureMessage(RecordingTarget.Failure.writerFailed) == "Could not save the recording.")
        precondition(RecordingModule.failureMessage(RecordingTarget.Failure.invalidFolder) == "Could not save the recording.")
        let countdown = RecordingModule(defaults: defaults, defaultFolder: root,
            makeSource: { source }, sleep: { try await Task.sleep(for: .seconds(60)) })
        countdown.start()
        let pending = Task { try await countdown.record(.display(1)) }
        while countdown.phase == .idle { await Task.yield() }
        precondition(countdown.phase == .countdown(3))
        countdown.stop()
        _ = await pending.result
        await countdown.waitUntilIdle()
        let afterCountdown = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mp4" }.count
        precondition(afterCountdown == publishedAfter + 2 && countdown.phase == .idle)
        print("PASS countdown switch-off writes nothing; paused switch-off publishes")
        print("PASS phase refresh hook, readable failures, switch-off publishes active take")
        print("PASS screen/area targets, cancelled selection, pause/resume, published URL reveal")
        print("PASS disabled/busy/permission danger failures, switch and idle availability")
    }
}

@MainActor final class ScreenRecordingSource: RecordingSource {
    var target: RecordingTarget?
    var starts = 0
    var denied = false
    var holdStop = false
    var stopContinuation: CheckedContinuation<Void, Never>?
    func prepare(_ target: RecordingTarget, frameRate: Int) async throws -> RecordingFormat {
        if denied { throw RecordingTarget.Failure.permissionDenied }
        self.target = target
        return RecordingFormat(width: 64, height: 64, frameRate: frameRate)
    }
    func start(writer: any RecordingWriting, onFailure: @escaping @MainActor (any Error) -> Void) async throws {
        starts += 1
        writer.begin(at: .zero)
    }
    func stop() async throws {
        if holdStop { await withCheckedContinuation { stopContinuation = $0 } }
    }
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
