// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/NetMerge/Model/*.swift Tinycast/Features/NetMerge/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/*Module.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/*Module+Core.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/NotchcastDownloadDestinations.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/DownloadsQueueController.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/DownloadsActivity.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/NotchcastDownloadCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/NotchcastDownloadCommands+Action.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/NotchcastDownloadRunner.swift
// notchcast-sources: Tinycast/Features/Notchcast/Downloads/NotchcastDownloadServices*.swift
// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Media/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Webpage/*.swift
// notchcast-sources: Tinycast/Features/Distill/Model/*.swift
// notchcast-sources: Tinycast/Features/Distill/Convert/*.swift
// notchcast-sources: Tinycast/Features/Distill/Service/DistillRunner.swift
// notchcast-sources: Tinycast/Features/Distill/Service/DistillTranscriber.swift
// notchcast-sources: Tinycast/Features/Distill/Service/DistillQueue.swift
// notchcast-sources: Tinycast/Features/Distill/Service/DownloadRunContext+Distill.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationAudioChunks.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationModel.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationWire.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Foundation
import Observation
import Synchronization

@main
@MainActor
struct NotchcastDownloadsWiringTest {
    private struct HeldRunner: DownloadRunner {
        let kind: String
        let tools: [DownloadTool] = []

        func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
            await context.report(DownloadProgress(fraction: 0.25, stage: "Holding"))
            try await Task.sleep(for: .seconds(60))
            return nil
        }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "notchcast-wiring-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "notchcast-downloads-wiring-test.\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let lookup = try makeTools(root: root)
        let webpageCalls = Mutex(0)
        var services = NotchcastDownloadServices(
            transcriber: DistillTranscriber { samples in
                precondition(samples == [0])
                return "Recognized speech."
            }, workDirectory: root.appending(path: "work"), tools: lookup)
        services.saveWebpage = { source, destination in
            webpageCalls.withLock { $0 += 1 }
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let output = destination.appending(path: "article.md")
            try Data(source.absoluteString.utf8).write(to: output)
            return output
        }
        let trash = root.appending(path: "trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        services.trash = { source in
            try FileManager.default.moveItem(at: source, to: trash.appending(path: source.lastPathComponent))
        }
        let downloads = DownloadsModule(
            preferences: preferences, services: services, file: root.appending(path: "downloads.json"),
            destination: root.appending(path: "Downloads"), report: { preconditionFailure($0) })
        let distill = DistillModule(
            preferences: preferences, services: services, file: root.appending(path: "distill.json"),
            linksFile: root.appending(path: "links.json"), destination: root.appending(path: "Distill/Raw"),
            report: { preconditionFailure($0) })
        let features = [NotchcastFeature.downloads, .downloadsAria2, .distill, .distillTimestamps, .distillConvert]
        precondition(features.allSatisfy { !preferences.isOn($0) }, "Downloads and Distill start off")
        features.forEach { preferences.set($0, true) }
        let controller = NotchcastModuleController([
            .init(requires: [.downloads], module: downloads), .init(requires: [.distill], module: distill)
        ], preferences: preferences)
        controller.run()
        await downloads.state.settle()
        await distill.state.settle()
        precondition(downloads.state.queue != nil && distill.state.queue?.maxConcurrent == 1)
        precondition(preferences.isOn(.distillTimestamps))
        precondition(features.allSatisfy { preferences.isOn($0) && $0.requiredGrants.isEmpty && !$0.needsIsland })
        try await testSpeechOwnership()
        testClipboard()
        try await testCommands(downloads: downloads, distill: distill, preferences: preferences)
        try await testMedia(downloads: downloads, preferences: preferences, root: root)
        try await testDistill(distill: distill, preferences: preferences, webpageCalls: webpageCalls)
        try await testConvert(distill: distill, preferences: preferences)
        try await testWebpageWithoutTools(services: services, preferences: preferences, root: root)
        try await testProgressAndStop(downloads: downloads, distill: distill, preferences: preferences)
        print("notchcast-downloads-wiring-test: passed switches, lifecycle, commands, live options, progress and engine seams")
    }

    private static func testSpeechOwnership() async throws {
        let core = AppCore()
        let services = NotchcastDownloadServices(core: core)
        let store = DictationModelStore.instances.last!
        precondition(store !== core.dictationModels)
        let text = try await services.transcriber.recognize([0])
        precondition(text == "Separate worker" && store.releases == 0)
        core.dictationModels.transcribing = true
        let waiting = Task { try await services.transcriber.recognizeWhenAvailable([0]) }
        try await Task.sleep(for: .milliseconds(150))
        precondition(store.calls == 1)
        core.dictationModels.transcribing = false
        _ = try await waiting.value
        precondition(store.loads == 1)
        store.installed = false
        do {
            _ = try await services.transcriber.recognize([0])
            preconditionFailure("Missing model must fail")
        } catch DictationWire.Failure.notInstalled {}
        precondition(store.releases == 0)
        store.installed = true
        let task = Task { try await services.transcriber.recognize([0]) }
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Cancellation must propagate") } catch is CancellationError {}
        precondition(store.releases == 0)
        await services.releaseSpeech()
        precondition(store.releases == 1)
        try await testSpeechLifetime(services: services, store: store)
        let count = DictationModelStore.instances.count
        let downloads = DownloadsModule(core: core, services: services)
        let distill = DistillModule(core: core, services: services)
        precondition(DictationModelStore.instances.count == count)
        let releases = store.releases
        downloads.stop()
        await downloads.state.settle()
        distill.stop()
        await distill.state.settle()
        precondition(store.releases == releases + 2)
    }

    private struct SpeechRunner: DownloadRunner {
        let kind = "distill"
        let tools: [DownloadTool] = []
        let transcriber: DistillTranscriber

        func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
            let pcm = context.destination.appending(path: UUID().uuidString + ".f32")
            try FileManager.default.createDirectory(at: context.destination, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: pcm) }
            try Data(count: (DistillAudioChunks.maximumSamples + 1) * 4).write(to: pcm)
            let segments = try await transcriber.transcribePCM(file: pcm)
            precondition(segments.count == 2)
            if job.source == "hold" { try await Task.sleep(for: .seconds(60)) }
            return nil
        }
    }

    private static func testSpeechLifetime(services: NotchcastDownloadServices, store: DictationModelStore) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = DownloadsQueueController(file: root.appending(path: "queue.json"), destination: root,
            maxConcurrent: 1, tools: DownloadToolLookup(), releaseSpeech: services.releaseSpeech,
            report: { preconditionFailure($0) })
        state.start { $0.register(SpeechRunner(transcriber: services.transcriber)) }
        await state.settle()
        let queue = state.queue!
        queue.enqueue(kind: "distill", sources: ["first", "second"])
        try await eventually { queue.jobs.allSatisfy { $0.state.isFinished } && store.releases == 2 }
        precondition(store.loads == 2 && store.calls == 6)
        queue.enqueue(kind: "distill", sources: ["hold"])
        try await eventually { store.calls == 8 }
        state.stop()
        await state.settle()
        precondition(store.loads == 3 && store.releases == 3)
    }

    private static func testClipboard() {
        precondition(NotchcastDownloadCommands.urls(in: """
        Read <https://example.com/a?q=1&keep=2> and https://example.org/Essay_(draft).
        https://example.com/a?q=1&keep=2 file:///tmp/file ftp://example.com/a www.example.com
        https://user:password@example.com/private user@example.com
        """) == ["https://example.com/a?q=1&keep=2", "https://example.org/Essay_(draft)"])
        precondition(NotchcastDownloadCommands.urls(in: "No links here").isEmpty)
    }

    private static func testCommands(
        downloads: DownloadsModule, distill: DistillModule, preferences: NotchcastPreferences
    ) async throws {
        var messages: [String] = []
        var opened: [URL] = []
        var commands = NotchcastDownloadCommands(downloads: downloads, distill: distill, preferences: preferences)
        commands.status = { messages.append($0) }
        commands.openFolder = { opened.append($0) }
        commands.clipboard = { "Nothing" }
        precondition(NotchcastDownloadCommands.Action.allCases.filter { commands.isEnabled($0) }.count == 9)
        await commands.perform(.video)
        precondition(messages.count == 1 && downloads.state.queue?.jobs.isEmpty == true)
        await commands.perform(.openDownloads)
        await commands.perform(.openDistill)
        precondition(opened == [downloads.state.destination, distill.state.destination])
        preferences.set(.downloads, false)
        precondition(NotchcastDownloadCommands.Action.allCases.filter { commands.isEnabled($0) }.count == 4)
        await commands.perform(.video)
        await drain()
        await downloads.state.settle()
        precondition(downloads.state.queue == nil && distill.state.queue != nil)
        preferences.set(.downloads, true)
        await drain()
        await downloads.state.settle()
        preferences.set(.distill, false)
        precondition(NotchcastDownloadCommands.Action.allCases.filter { commands.isEnabled($0) }.count == 5)
        await commands.perform(.addDistill)
        await drain()
        await distill.state.settle()
        precondition(distill.state.queue == nil && downloads.state.queue != nil)
        preferences.set(.distill, true)
        await drain()
        await distill.state.settle()
        preferences.set(.distillConvert, false)
        precondition(NotchcastDownloadCommands.Action.allCases.filter { commands.isEnabled($0) }.count == 8)
        await commands.perform(.convert)
        preferences.set(.distillConvert, true)
        preferences.set(.island, false)
        await drain()
        precondition(downloads.state.queue != nil && distill.state.queue != nil)
        commands.clipboard = { "https://youtu.be/abc https://www.youtube.com/watch?v=abc&utm_source=x" }
        await commands.perform(.addDistill)
        precondition(distill.links?.links.count == 1 && distill.state.queue?.jobs.isEmpty == true)
    }

    private static func testMedia(downloads: DownloadsModule, preferences: NotchcastPreferences, root: URL) async throws {
        let queue = downloads.state.queue!
        let calls = root.appending(path: "tools/yt-dlp.calls")
        preferences.set(.downloadsAria2, false)
        queue.enqueue(kind: "video", sources: ["https://example.com/video"])
        try await eventually { queue.jobs.last?.state.isFinished == true }
        precondition(queue.jobs.last?.state == .done)
        try check(!String(contentsOf: calls, encoding: .utf8).contains("--downloader"))
        queue.register(HeldRunner(kind: "hold"))
        let blockers = queue.enqueue(kind: "hold", sources: ["a", "b", "c"])
        queue.enqueue(kind: "audio", sources: ["https://example.com/audio"])
        precondition(queue.jobs.last?.state == .waiting)
        preferences.set(.downloadsAria2, true)
        for job in blockers { queue.cancel(job.id) }
        try await eventually { queue.jobs.last?.state.isFinished == true }
        precondition(queue.jobs.last?.state == .done && downloads.state.queue === queue)
        try check(String(contentsOf: calls, encoding: .utf8).contains("--downloader"))
        queue.enqueue(kind: "transcript", sources: ["https://www.youtube.com/watch?v=captionless"])
        try await eventually { queue.jobs.last?.state.isFinished == true }
        precondition(queue.jobs.last?.state == .done)
        let transcript = URL(filePath: queue.jobs.last!.output!)
        try check(String(contentsOf: transcript, encoding: .utf8) == "Recognized speech.\n")
        precondition(transcript.lastPathComponent == "Sample [sample-id].txt")
        queue.enqueue(kind: "transcript", sources: ["https://www.youtube.com/watch?v=again"])
        try await eventually { queue.jobs.last?.state.isFinished == true }
        precondition(URL(filePath: queue.jobs.last!.output!).lastPathComponent == "Sample [sample-id] (2).txt")
        queue.enqueue(kind: "transcript", sources: ["https://example.com/article"])
        try await eventually { queue.jobs.last?.state.isFinished == true }
        precondition(queue.jobs.last?.state == .failed)
        precondition(queue.jobs.last?.detail?.contains("supported media link") == true)
    }

    private static func testDistill(
        distill: DistillModule, preferences: NotchcastPreferences, webpageCalls: borrowing Mutex<Int>
    ) async throws {
        let queue = distill.state.queue!
        try await distill.run()
        try await eventually { queue.jobs.allSatisfy { $0.state.isFinished } }
        precondition(distill.links?.links.isEmpty == true && queue.jobs.count == 1 && queue.jobs[0].state == .done)
        try check(String(contentsOfFile: queue.jobs[0].output!, encoding: .utf8).hasPrefix("[00:00:00]"))
        preferences.set(.distillTimestamps, false)
        try distill.links?.add(text: "https://youtu.be/next https://example.com/article", now: .now)
        try await distill.run()
        try await eventually { queue.jobs.allSatisfy { $0.state.isFinished } }
        precondition(queue.jobs.count == 3 && queue.jobs.allSatisfy { $0.state == .done })
        try check(!String(contentsOfFile: queue.jobs[1].output!, encoding: .utf8).contains("[00:00:00]"))
        precondition(webpageCalls.withLock { $0 } == 1 && distill.state.queue === queue)
        try await distill.run()
        precondition(queue.jobs.count == 3)
    }

    private static func testConvert(distill: DistillModule, preferences: NotchcastPreferences) async throws {
        let queue = distill.state.queue!
        let folder = distill.state.destination.appending(path: "convert")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("<h1>Article</h1><p>Readable HTML.</p>".utf8).write(to: folder.appending(path: "article.html"))
        try Data("""
        Content-Type: text/html; charset=utf-8
        Content-Location: https://example.com/base/

        <h1>Saved Page</h1><a href="child">Child</a>
        """.utf8).write(to: folder.appending(path: "saved.mhtml"))
        try Data([1]).write(to: folder.appending(path: "recording.mp3"))
        queue.enqueue(kind: "convert", sources: [folder.path])
        try await eventually { queue.jobs.last?.state.isFinished == true }
        precondition(queue.jobs.last?.state == .done, queue.jobs.last?.detail ?? "Conversion failed")
        try check(String(contentsOf: folder.appending(path: "article.md"), encoding: .utf8).contains("# Article"))
        try check(String(contentsOf: folder.appending(path: "saved.md"), encoding: .utf8)
            .contains("https://example.com/base/child"))
        try check(String(contentsOf: folder.appending(path: "recording.md"), encoding: .utf8)
            .contains("Recognized speech."))
        precondition(!FileManager.default.fileExists(atPath: folder.appending(path: "article.html").path))
        precondition(FileManager.default.fileExists(atPath: folder.appending(path: "recording.mp3").path))
        queue.register(HeldRunner(kind: "convert"))
        queue.enqueue(kind: "convert", sources: [folder.path, folder.path])
        preferences.set(.distillConvert, false)
        await drain()
        precondition(queue.jobs.suffix(2).allSatisfy { $0.state == .cancelled })
        queue.enqueue(kind: "convert", sources: [folder.path])
        precondition(queue.jobs.last?.state == .failed)
        preferences.set(.distillConvert, true)
        await drain()
        distill.convert()
        try await eventually { queue.jobs.last?.state.isFinished == true }
        precondition(queue.jobs.last?.state == .done)
    }

    private static func testWebpageWithoutTools(
        services: NotchcastDownloadServices, preferences: NotchcastPreferences, root: URL
    ) async throws {
        var services = services
        services.tools = DownloadToolLookup(directories: [], home: root)
        let module = DistillModule(preferences: preferences, services: services,
                                  file: root.appending(path: "web-only.json"), linksFile: root.appending(path: "web-links.json"),
                                  destination: root.appending(path: "web-only"), report: { preconditionFailure($0) })
        module.start()
        await module.state.settle()
        try module.links?.add(text: "https://example.com/article", now: .now)
        try await module.run()
        try await eventually { module.state.queue?.jobs.last?.state.isFinished == true }
        precondition(module.state.queue?.jobs.last?.state == .done)
        module.stop()
        await module.state.settle()
    }

    private static func testProgressAndStop(
        downloads: DownloadsModule, distill: DistillModule, preferences: NotchcastPreferences
    ) async throws {
        let queue = downloads.state.queue!
        queue.register(HeldRunner(kind: "hold"))
        queue.enqueue(kind: "hold", sources: ["first", "second"])
        try await eventually { downloads.activity.fraction == 0.25 }
        precondition(downloads.activity.runningCount == 2 && downloads.activity.currentTitle == "first")
        precondition(downloads.activity.stage == "Holding")
        let observed = Mutex(false)
        withObservationTracking { _ = downloads.activity } onChange: { observed.withLock { $0 = true } }
        preferences.set(.downloads, false)
        await drain()
        await downloads.state.settle()
        precondition(queue.jobs.suffix(2).allSatisfy { $0.state == .interrupted })
        precondition(downloads.state.queue == nil && downloads.activity.runningCount == 0 && observed.withLock { $0 })
        let distillQueue = distill.state.queue!
        distillQueue.register(HeldRunner(kind: "hold"))
        distillQueue.enqueue(kind: "hold", sources: ["distill"])
        try await eventually { distill.activity.runningCount == 1 }
        preferences.set(.distill, false)
        await drain()
        await distill.state.settle()
        precondition(distill.state.queue == nil && distill.links == nil)
        precondition(distillQueue.jobs.last?.state == .interrupted)
        downloads.start()
        downloads.stop()
        downloads.start()
        await downloads.state.settle()
        precondition(downloads.state.queue != nil && downloads.state.queue !== queue)
        downloads.stop()
        await downloads.state.settle()
    }

    private static func makeTools(root: URL) throws -> DownloadToolLookup {
        let folder = root.appending(path: "tools")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let downloader = """
        #!/bin/sh
        printf '%s\\n' "$@" >> "$0.calls"
        mode=download
        dest=''
        template=''
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --paths) shift; dest="$1";;
            -o) shift; template="$1";;
            --dump-single-json) mode=metadata;;
            --write-subs|--write-auto-subs) mode=captions;;
            --print) shift; [ "$1" != '%(language)s' ] || mode=language;;
          esac
          shift
        done
        case "$mode" in
          language) printf 'en\\n';;
          metadata) printf '{"title":"Sample","id":"sample-id","channel":"Channel"}\\n';;
          captions) exit 0;;
          download)
            if [ -n "$dest" ]; then
              printf x > "$dest/movie.mp4"
              printf 'MEDIA_FILE "%s/movie.mp4"\\n' "$dest"
            else
              printf x > "${template%/*}/audio.m4a"
            fi;;
        esac
        """
        let ffmpeg = """
        #!/bin/sh
        for arg in "$@"; do output="$arg"; done
        printf '\\000\\000\\000\\000' > "$output"
        """
        for (name, script) in [("yt-dlp", downloader), ("ffmpeg", ffmpeg), ("aria2c", "#!/bin/sh\nexit 0\n")] {
            let file = folder.appending(path: name)
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        return DownloadToolLookup(directories: [folder], home: root)
    }

    private static func drain() async { for _ in 0..<30 { await Task.yield() } }

    private static func check(_ condition: @autoclosure () throws -> Bool) rethrows {
        let value = try condition()
        precondition(value)
    }

    private static func eventually(file: StaticString = #filePath, line: UInt = #line,
                                   _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for queue", file: file, line: line)
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
enum NotchcastDownloadLauncherCommands {
    static weak var downloads: DownloadsModule?
    static weak var distill: DistillModule?
    static func trackAvailability(_ core: AppCore) {}
}

@MainActor
final class AppCore {
    enum Tone { case danger }
    func showMessage(_ message: String, tone: Tone) { preconditionFailure(message) }
    struct Settings {
        var dictationIdleRelease = DictationIdleRelease.never
        var dictationModel = DictationModel.allCases[0]
    }
    var settings = Settings()
    let dictationModels = DictationModelStore(idleRelease: .never)
}

enum DictationIdleRelease { case never }

@MainActor
final class DictationModelStore {
    static var instances: [DictationModelStore] = []
    var transcribing = false
    var installed = true
    var releases = 0
    var loads = 0
    var calls = 0
    var loaded = false

    init(idleRelease: DictationIdleRelease) { Self.instances.append(self) }
    func refreshInstalledModels() {}
    func transcribe(_ samples: [Float], model: DictationModel, language: String?) async throws -> String {
        try Task.checkCancellation()
        guard installed else { throw DictationWire.Failure.notInstalled }
        guard !transcribing else { throw DictationWire.Failure.busy }
        calls += 1
        if !loaded { loads += 1; loaded = true }
        return "Separate worker"
    }
    func release() async { releases += 1; loaded = false }
}
