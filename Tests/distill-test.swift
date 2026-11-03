import Foundation
import Synchronization

@main
@MainActor
struct DistillTest {
    @MainActor private final class Recognition {
        var counts = [Int]()
        var answers = ["A first chunk ends with the shared words.", "THE shared words, followed by new speech."]

        func transcribe(_ samples: [Float]) -> String {
            counts.append(samples.count)
            return answers.removeFirst()
        }
    }

    @MainActor
    static func main() async throws {
        if CommandLine.arguments.contains("--live") {
            try await live()
            return
        }
        let environment = ProcessInfo.processInfo.environment
        let scratch = environment["DISTILL_TEST_ROOT"].map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory
        let root = scratch.appending(path: "fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        testLinks()
        testNaming()
        testChunkPlan()
        try testLegacy(root: root)
        try testQueue(root: root)
        try testPublication(root: root)
        try await testTranscription(root: root)
        try await testRunner(root: root)
        print("Distill passed: links, dedupe, naming, chunks, timestamps, legacy import, publication and cancellation")
    }

    private static func testLinks() {
        let links = LinkCleaner.links(in: """
        <https://youtu.be/AbC_123-x?si=share> https://www.youtube.com/shorts/AbC_123-x
        https://m.youtube.com/watch?v=AbC_123-x&t=10 https://example.com/article/?utm_source=a#heading
        http://www.example.com/article https://twitter.com/person/status/123?s=20
        https://x.com/person/status/123?t=tracking https://example.com/Essay_(draft).
        """)
        precondition(links == ["https://www.youtube.com/watch?v=AbC_123-x", "https://example.com/article",
                               "https://twitter.com/person/status/123", "https://example.com/Essay_(draft)"])
        precondition(LinkCleaner.clean("file:///etc/passwd") == nil)
        precondition(LinkCleaner.clean("https://user:secret@example.com/") == nil)
        precondition(LinkCleaner.clean("https://youtube.com/watch") == nil)
        precondition(LinkCleaner.clean("https://youtu.be/a%26b") == nil)
        precondition(LinkCleaner.clean("https://EXAMPLE.com:443/?q=Keep&utm_medium=x") == "https://example.com?q=Keep")
        precondition(LinkCleaner.key("https://example.com/Case") != LinkCleaner.key("https://example.com/case"))
        let arguments = YtDlpAudio.audioArguments(link: "https://example.com/video", folder: URL(filePath: "/test"))
        precondition(arguments.contains("--ignore-config") && arguments.contains("--no-playlist"))
        precondition(!arguments.contains("--cookies-from-browser") && arguments.suffix(2).first == "--")
    }

    private static func testNaming() {
        precondition(DistillTranscript.fileName(channel: "Channel", title: "Title") == "Channel - Title.txt")
        let name = DistillTranscript.fileName(channel: "../Channel/Name", title: "Title: with \\ bad<>\"|?*\u{0}characters")
        precondition(!name.hasPrefix("."))
        precondition(!name.contains(where: { "/:\\<>\"|?*\u{0}".contains($0) }))
        precondition(DistillTranscript.fileName(channel: "", title: "...") == "Untitled.txt")
        let long = DistillTranscript.fileName(
            channel: String(repeating: "猫", count: 200), title: String(repeating: "🐈", count: 200))
        precondition(long.utf8.count <= 207)
        precondition(DistillTranscript.clock(3661) == "[01:01:01]")
        precondition(DistillTranscript.clock(-1) == "[00:00:00]")
    }

    private static func testChunkPlan() {
        precondition(DistillAudioChunks.plan(sampleCount: 0).isEmpty)
        let maximum = Int64(DistillAudioChunks.maximumSamples)
        precondition(DistillAudioChunks.plan(sampleCount: maximum).count == 1)
        let chunks = DistillAudioChunks.plan(sampleCount: maximum * 3 + 17)
        precondition(chunks.count == 4 && chunks.first?.offset == 0)
        precondition(chunks.last.map { $0.offset + Int64($0.count) } == maximum * 3 + 17)
        for (previous, next) in zip(chunks, chunks.dropFirst()) {
            precondition(previous.offset + Int64(previous.count) - next.offset == Int64(DistillAudioChunks.overlapSamples))
            precondition(next.count <= DictationWire.maximumSamples && next.start > previous.start)
        }
        precondition(DistillAudioChunks.removingOverlap(
            previous: "A shared phrase.", next: "SHARED phrase, new words") == "new words")
        precondition(DistillAudioChunks.removingOverlap(previous: "yes", next: "yes, yes") == "yes, yes")
        precondition(DistillAudioChunks.removingOverlap(previous: "Other content", next: "Different words") == "Different words")
    }

    private static func testLegacy(root: URL) throws {
        let fixture = Data("""
        {"entries":[
          {"canonicalUrl":"https://youtu.be/abc?si=a","addedAt":"2026-01-02T00:00:00Z","state":"queued"},
          {"url":"https://example.com/post","addedAt":1767225600000,"status":"failed","lastError":"offline","attempts":2},
          {"url":"https://youtube.com/watch?v=abc","state":"queued"},
          {"url":"https://example.com/done","state":"done"},
          {"url":"https://example.com/running","state":"running"},
          {"url":"file:///invalid","state":"failed"}
        ]}
        """.utf8)
        let legacy = root.appending(path: "legacy.json")
        try fixture.write(to: legacy)
        let queueFile = root.appending(path: "imported.json")
        let queue = try DistillQueue(file: queueFile)
        try check(queue.importLegacy(from: legacy, now: .distantPast) == 2)
        precondition(queue.links.map(\.state) == [.failed, .waiting])
        precondition(queue.links.first?.attempts == 2 && queue.links.first?.detail == "offline")
        try check(Data(contentsOf: legacy) == fixture)
        try queue.remove(queue.links[0].id)
        let reloaded = try DistillQueue(file: queueFile)
        try check(reloaded.importLegacy(from: legacy, now: .distantPast) == 0)
        precondition(reloaded.links.count == 1)
        let keyed = try LegacyDistillQueue.parse(Data("""
        {"entries":{"https://example.com/keyed":{"state":"queued"}}}
        """.utf8), now: .distantPast)
        precondition(keyed.count == 1)
        let orion = try LegacyDistillQueue.parse(Data("""
        [{"url":"https://example.com/orion","stage":"queued","added":"2026-01-01T00:00:00Z"}]
        """.utf8), now: .distantPast)
        precondition(orion.count == 1 && orion[0].added != .distantPast)
    }

    @MainActor
    private static func testQueue(root: URL) throws {
        let file = root.appending(path: "queue.json")
        let queue = try DistillQueue(file: file)
        try check(queue.add(text: "https://youtu.be/one https://youtube.com/watch?v=one", now: .distantPast).count == 1)
        let id = queue.links[0].id
        try queue.fail(id, detail: "offline")
        try check(queue.add(text: "https://youtu.be/one", now: .distantPast).isEmpty)
        try check(DistillQueue(file: file).links[0].state == .failed)
        try queue.retry(id)
        precondition(queue.links[0].state == .waiting && queue.links[0].attempts == 1 && queue.links[0].detail == nil)
        try queue.remove(id)
        try check(queue.add(text: "https://youtu.be/one", now: .distantPast).count == 1)
        let invalid = try DistillQueue(file: root.appending(path: "queue.json/invalid.json"))
        do {
            _ = try invalid.add(text: "https://example.com/one", now: .distantPast)
            preconditionFailure("Unwritable queue succeeded")
        } catch { precondition(invalid.links.isEmpty) }
    }

    private static func testPublication(root: URL) throws {
        let folder = root.appending(path: "Raw")
        let first = try DistillRunner.save("first\n", name: "Channel - Title.txt", in: folder)
        let second = try DistillRunner.save("second\n", name: "Channel - Title.txt", in: folder)
        precondition(second.lastPathComponent == "Channel - Title (2).txt")
        try check(String(contentsOf: first, encoding: .utf8) == "first\n")
        try check(String(contentsOf: second, encoding: .utf8) == "second\n")
        do {
            _ = try DistillRunner.save("", name: "Empty.txt", in: folder)
            preconditionFailure("Empty transcript published")
        } catch {}
        try check(FileManager.default.contentsOfDirectory(atPath: folder.path).count == 2)
    }

    @MainActor
    private static func testTranscription(root: URL) async throws {
        let pcm = root.appending(path: "fixture.f32")
        precondition(FileManager.default.createFile(atPath: pcm.path, contents: nil))
        let handle = try FileHandle(forWritingTo: pcm)
        let count = DistillAudioChunks.maximumSamples + 16_000
        try handle.truncate(atOffset: UInt64(count * 4))
        try handle.close()
        let recognition = Recognition()
        let transcriber = DistillTranscriber { recognition.transcribe($0) }
        let progress = Mutex<[Int]>([])
        let result = try await transcriber.transcribePCM(file: pcm) { completed, _ in
            progress.withLock { $0.append(completed) }
        }
        precondition(recognition.counts == [DistillAudioChunks.maximumSamples, 48_000])
        precondition(result.count == 2 && result[1].start == 238)
        precondition(result[1].text == "followed by new speech.")
        precondition(DistillTranscript.text(result, times: true).contains("[00:03:58] followed by new speech."))
        precondition(!DistillTranscript.text(result, times: false).contains("[00:"))
        precondition(progress.withLock { $0 } == [1, 2])
        let cancelled = Task { try await transcriber.transcribePCM(file: pcm) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancelled transcription succeeded")
        } catch is CancellationError {}
        precondition(recognition.counts.count == 2)
        try Data([0, 1, 2]).write(to: pcm)
        do {
            _ = try await transcriber.transcribePCM(file: pcm)
            preconditionFailure("Corrupt PCM accepted")
        } catch is CocoaError {}
    }

    @MainActor
    private static func testRunner(root: URL) async throws {
        let calls = Mutex<[String]>([])
        let execution = DistillExecution { tool, arguments in
            calls.withLock { $0.append(tool) }
            if arguments.contains("--dump-single-json") { return #"{"title":"Title","channel":"Channel"}"# }
            if tool == "yt-dlp", let index = arguments.firstIndex(of: "-o") {
                let path = arguments[index + 1].replacingOccurrences(of: "%(ext)s", with: "m4a")
                try Data([0]).write(to: URL(filePath: path))
            }
            if tool == "ffmpeg", let path = arguments.last {
                try Data(repeating: 0, count: 64_000).write(to: URL(filePath: path))
            }
            return ""
        }
        let work = root.appending(path: "runner-work")
        let runner = DistillRunner(transcriber: DistillTranscriber { _ in "A transcript." }, workDirectory: work) { _, target in
            target.appending(path: "webpage.md")
        }
        let result = try await runner.run(source: "https://youtu.be/abc", destination: root.appending(path: "runner-output"),
                                          execution: execution)
        try check(String(contentsOf: result, encoding: .utf8) == "A transcript.\n")
        precondition(calls.withLock { $0 } == ["yt-dlp", "yt-dlp", "ffmpeg"])
        try check(FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
        let page = try await runner.run(source: "https://example.com/article", destination: root, execution: execution)
        precondition(page.lastPathComponent == "webpage.md" && calls.withLock { $0.count } == 3)
        let ready = AsyncStream<Void>.makeStream()
        let slow = DistillRunner(transcriber: DistillTranscriber { _ in
            ready.continuation.yield(())
            try await Task.sleep(for: .seconds(60))
            return "Late text"
        }, workDirectory: work, saveWebpage: runner.saveWebpage)
        let cancelled = Task {
            try await slow.run(source: "https://youtu.be/cancelled", destination: root.appending(path: "cancelled-output"),
                               execution: execution)
        }
        var iterator = ready.stream.makeAsyncIterator()
        _ = await iterator.next()
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            preconditionFailure("Cancelled runner published a transcript")
        } catch is CancellationError {}
        precondition(!FileManager.default.fileExists(atPath: root.appending(path: "cancelled-output").path))
        try check(FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
    }

    @MainActor
    private static func live() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 6 else {
            fatalError("--live <pack-directory> <helper-executable> <model-cache> <public-video-url>")
        }
        let root = URL(filePath: arguments[2])
        let executable = URL(filePath: arguments[3])
        let modelRoot = URL(filePath: arguments[4])
        if let existing = ProcessInfo.processInfo.environment["DISTILL_EXISTING_MODEL"] {
            try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
            let link = modelRoot.appending(path: DictationModel.ultra.folderName)
            if !FileManager.default.fileExists(atPath: link.path) {
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(filePath: existing))
            }
        }
        let store = DictationModelStore(idleRelease: .never, root: modelRoot) { try DictationWorker(executable: executable) }
        let model = DictationModel.allCases.filter { store.isInstalled($0) }
            .min { $0.approximateInstalledMegabytes < $1.approximateInstalledMegabytes } ?? .redux
        if !store.isInstalled(model) {
            print("No model installed in the build cache; downloading Redux with the upstream downloader")
            try await store.download(model)
        }
        do {
            let execution = DistillExecution { tool, arguments in
                try await spawn(tool: tool, arguments: arguments, root: root.appending(path: "commands"))
            }
            let runner = DistillRunner(
                transcriber: store.distillTranscriber(model: model), workDirectory: root.appending(path: "Work")
            ) { _, _ in throw CocoaError(.fileReadUnsupportedScheme) }
            let output = try await runner.run(
                source: arguments[5], destination: root.appending(path: "Raw"), execution: execution)
            let text = try String(contentsOf: output, encoding: .utf8)
            print("Live Distill model: \(model.rawValue)")
            print("Live Distill output: \(output.path)")
            print(text)
            await store.stop()
        } catch {
            await store.stop()
            throw error
        }
    }

    private static func check(_ condition: @autoclosure () throws -> Bool) rethrows {
        guard try condition() else { preconditionFailure("Distill assertion failed") }
    }

    @concurrent
    private nonisolated static func spawn(tool: String, arguments: [String], root: URL) async throws -> String {
        try Task.checkCancellation()
        let process = Process()
        let cancelled = Mutex(false)
        let task = Task.detached {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let output = root.appending(path: "\(UUID()).stdout")
            let errors = root.appending(path: "\(UUID()).stderr")
            try Data().write(to: output)
            try Data().write(to: errors)
            let stdout = try FileHandle(forWritingTo: output)
            let stderr = try FileHandle(forWritingTo: errors)
            defer { try? stdout.close(); try? stderr.close() }
            process.executableURL = URL(filePath: "/usr/bin/env")
            process.arguments = [tool] + arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr
            let exit = try cancelled.withLock { cancelled in
                guard !cancelled else { throw CancellationError() }
                return try process.runObservingExit()
            }
            exit.wait()
            try Task.checkCancellation()
            guard process.terminationStatus == 0 else {
                throw NSError(domain: "DistillLiveCommand", code: Int(process.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: try String(contentsOf: errors, encoding: .utf8)
                ])
            }
            return try String(contentsOf: output, encoding: .utf8)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
            cancelled.withLock {
                $0 = true
                if process.isRunning { process.terminate() }
            }
        }
    }
}
