// notchcast-sources: -target arm64-apple-macos26.0 Tinycast/Features/CaptureRecording/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingModule.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingFiles.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingWriting.swift
// notchcast-sources: Tinycast/Features/CaptureRecording/Service/RecordingSource.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
import CoreMedia
import Foundation

@main
struct RecordingModuleTests {
    @MainActor static func main() async throws {
        let suite = "recording-module-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = ScreenRecordingSource()
        let module = RecordingModule(defaults: defaults, defaultFolder: root, makeSource: { source }, sleep: {})
        let preferences = NotchcastPreferences(suiteName: suite)
        preferences.set(.recording, false)
        let controller = NotchcastModuleController([.init(requires: [.recording], module: module)], preferences: preferences)
        controller.run()
        precondition(!module.enabled)
        preferences.set(.recording, true)
        await settle { module.enabled }
        try await module.record(.display(1))
        precondition(source.starts == 1 && module.phase == .recording)
        do {
            _ = try await module.finish()
            preconditionFailure("failed writer must throw")
        } catch TestFailure.diskFull { }
        precondition(module.lastError?.localizedDescription == "Synthetic disk full")
        precondition(module.phase == .idle)
        try await module.record(.window(2))
        preferences.set(.recording, false)
        await settle { !module.enabled }
        await module.waitUntilIdle()
        precondition(source.stops > 0 && module.phase == .idle)
        print("PASS recording module switch, record entry point, writer failure message and teardown")
    }

    @MainActor private static func settle(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        preconditionFailure("module switch did not settle")
    }
}

private enum TestFailure: LocalizedError {
    case diskFull
    var errorDescription: String? { "Synthetic disk full" }
}

@MainActor final class ScreenRecordingSource: RecordingSource {
    var starts = 0
    var stops = 0
    func prepare(_ target: RecordingTarget, frameRate: Int) async throws -> RecordingFormat {
        RecordingFormat(width: 64, height: 64, frameRate: frameRate)
    }
    func start(writer: any RecordingWriting, onFailure: @escaping @MainActor (any Error) -> Void) async throws {
        starts += 1
        writer.begin(at: .zero)
    }
    func stop() async throws { stops += 1 }
}

final class RecordingWriter: RecordingWriting {
    static func create(url: URL, format: RecordingFormat) async throws -> RecordingWriter { RecordingWriter() }
    func begin(at time: CMTime) {}
    func append(_ sample: CMSampleBuffer, track: RecordingFormat.Track) throws {}
    func setPaused(_ paused: Bool, at time: CMTime) {}
    func finish(at time: CMTime) async throws { throw TestFailure.diskFull }
    func cancel() async {}
}
