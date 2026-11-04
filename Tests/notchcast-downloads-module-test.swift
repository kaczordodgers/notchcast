// notchcast-sources: Tinycast/Features/Notchcast/Downloads/DownloadsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/DownloadsQueueController.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/DownloadsActivity.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/NotchcastDownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
import Foundation

enum MediaArguments {
    enum Format: String { case video, audio }
}

struct MediaDownloadRunner: DownloadRunner {
    let format: MediaArguments.Format
    var kind: String { format.rawValue }
    let tools: [DownloadTool] = []

    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
        await context.report(DownloadProgress(stage: job.options["aria2Enabled"]))
        try await Task.sleep(for: .seconds(60))
        return nil
    }
}

struct WebpageRunner: DownloadRunner {
    let kind = "webpage"
    let tools: [DownloadTool] = []
    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? { nil }
}

struct NotchcastDownloadServices: Sendable {
    var tools: DownloadToolLookup
    var releaseSpeech: @MainActor @Sendable () async -> Void
    let transcriptRunner = FakeTranscriptRunner()
}

struct FakeTranscriptRunner: DownloadRunner {
    let kind = "transcript"
    let tools: [DownloadTool] = []
    func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? { nil }
}

@main
@MainActor
struct DownloadsModuleTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let suite = "downloads-module-test.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: root)
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        }
        let preferences = NotchcastPreferences(suiteName: suite)
        var releases = 0
        let services = NotchcastDownloadServices(
            tools: DownloadToolLookup(directories: [], home: root), releaseSpeech: { releases += 1 })
        let module = DownloadsModule(preferences: preferences, services: services,
            file: root.appending(path: "queue.json"), destination: root,
            report: { preconditionFailure($0) })
        let controller = NotchcastModuleController([
            .init(requires: [.downloads], module: module)
        ], preferences: preferences)
        preferences.set(.downloads, false)
        controller.run()
        precondition(module.state.queue == nil)
        preferences.set(.downloads, true)
        try await eventually { module.state.queue != nil }
        let queue = module.state.queue!
        module.start()
        await module.state.settle()
        precondition(module.state.queue === queue)
        for enabled in [false, true] {
            preferences.set(.downloadsAria2, enabled)
            let job = queue.enqueue(kind: "video", sources: ["fake-video"]).first!
            try await eventually { queue.jobs.first { $0.id == job.id }?.progress?.stage == String(enabled) }
            queue.cancel(job.id)
            precondition(module.state.queue === queue)
        }
        for kind in ["audio", "transcript", "webpage"] {
            queue.enqueue(kind: kind, sources: ["fake-source"])
        }
        try await eventually { queue.jobs.suffix(2).allSatisfy { $0.state == .done } }
        try await eventually { module.activity.runningCount == 1 }
        var commandStarted = false
        var commandCancelled = false
        let command = Task {
            commandStarted = true
            do {
                try await Task.sleep(for: .seconds(60))
            } catch is CancellationError {
                commandCancelled = true
            } catch {
                preconditionFailure(String(describing: error))
            }
        }
        module.commandTask = command
        try await eventually { commandStarted }
        preferences.set(.downloads, false)
        try await eventually { module.state.queue == nil }
        await module.state.settle()
        await command.value
        precondition(commandCancelled && module.commandTask == nil)
        precondition(module.activity.runningCount == 0 && releases > 0)
        precondition(queue.jobs.first { $0.kind == "audio" }?.state == .interrupted)
        module.start()
        module.stop()
        module.start()
        await module.state.settle()
        precondition(module.state.queue != nil && module.state.queue !== queue)
        module.stop()
        await module.state.settle()
        print("notchcast-downloads-module-test: passed lifecycle, switches and command cancellation")
    }

    private static func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
