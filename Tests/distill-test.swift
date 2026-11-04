// notchcast-sources: Tinycast/Features/Distill/Model/*.swift
// notchcast-sources: Tinycast/Features/Distill/Service/DistillTranscriber.swift
// notchcast-sources: Tinycast/Features/Distill/Service/DistillRunner.swift
// notchcast-sources: Tinycast/Features/Distill/Service/DistillQueue.swift
// notchcast-sources: Tinycast/Features/Distill/Service/DownloadRunContext+Distill.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationAudioChunks.swift
// notchcast-sources: Tinycast/Features/Dictation/Model/DictationModel.swift
// notchcast-sources: Tinycast/Features/Dictation/Service/DictationWire.swift
// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/DownloadRunner.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/DownloadRunContext.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import Foundation
import Synchronization

@main
@MainActor
struct DistillTest {
    @MainActor private final class Recognition {
        var counts = [Int]()
        var answers = ["A first chunk ends.", "New speech follows."]

        func transcribe(_ samples: [Float]) -> String {
            counts.append(samples.count)
            return answers.removeFirst()
        }
    }

    @MainActor
    static func main() async throws {
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
        try await testBusy()
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
        let maximum = DistillAudioChunks.maximumSamples
        var samples = [Float](repeating: 1, count: maximum)
        let silence = (maximum - 24_000)..<(maximum - 20_800)
        samples.replaceSubrange(silence, with: repeatElement(Float.zero, count: silence.count))
        let cut = DistillAudioChunks.cut(in: samples, final: false)
        precondition(silence.contains(cut) && cut < DictationWire.maximumSamples)
        precondition(DistillAudioChunks.cut(in: samples, final: true) == maximum)
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
        precondition(recognition.counts == [DistillAudioChunks.maximumSamples - 1_600, 17_600])
        precondition(recognition.counts.reduce(0, +) == count)
        precondition(result.count == 2 && result[1].start == 239.9)
        precondition(result[1].text == "New speech follows.")
        precondition(DistillTranscript.text(result, times: true).contains("[00:03:59] New speech follows."))
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
    private static func testBusy() async throws {
        var attempts = 0
        let retrying = DistillTranscriber { _ in
            attempts += 1
            if attempts <= 3 { throw DictationWire.Failure.busy }
            return "Ready"
        }
        let text = try await retrying.recognizeWhenAvailable([0])
        precondition(text == "Ready" && attempts == 4)
        let ready = AsyncStream<Void>.makeStream()
        let busy = DistillTranscriber { _ in
            ready.continuation.yield(())
            throw DictationWire.Failure.busy
        }
        let task = Task { try await busy.recognizeWhenAvailable([0]) }
        var iterator = ready.stream.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        do {
            _ = try await task.value
            preconditionFailure("Busy retry ignored cancellation")
        } catch is CancellationError {}
        let failed = DistillTranscriber { _ in throw DictationWire.Failure.notInstalled }
        do {
            _ = try await failed.recognizeWhenAvailable([0])
            preconditionFailure("Non-busy error retried")
        } catch DictationWire.Failure.notInstalled {}
    }

    @MainActor
    private static func testRunner(root: URL) async throws {
        let bin = root.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = """
        #!/usr/bin/python3
        import sys, json
        a = sys.argv
        if '--dump-single-json' in a:
            print(json.dumps({'title': 'Title', 'channel': 'Channel'}))
        elif '-o' in a:
            open(a[a.index('-o') + 1].replace('%(ext)s', 'm4a'), 'wb').write(b'0')
        else:
            open(a[-1], 'wb').write(bytes(64000))
        """
        for tool in ["yt-dlp", "ffmpeg"] {
            let file = bin.appending(path: tool)
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        let stages = Mutex<[String]>([])
        let context = DownloadRunContext(
            destination: root.appending(path: "runner-output"),
            tools: DownloadToolLookup(directories: [bin]),
            report: { value in stages.withLock { $0.append(value.stage ?? "") } })
        let work = root.appending(path: "runner-work")
        let runner = DistillRunner(transcriber: DistillTranscriber { _ in "A transcript." }, workDirectory: work) { _, target in
            target.appending(path: "webpage.md")
        }
        let job = DownloadJob(id: UUID().uuidString, kind: "distill", source: "https://youtu.be/abc",
                              title: "Fixture", created: .distantPast)
        let registered: any DownloadRunner = runner
        precondition(registered.kind == "distill" && registered.tools == [.ytDlp, .ffmpeg])
        let result = try await registered.run(job, context: context)!
        try check(String(contentsOf: result, encoding: .utf8) == "A transcript.\n")
        precondition(stages.withLock { $0 } == ["Transcribing 1 of 1"])
        try check(FileManager.default.contentsOfDirectory(atPath: work.path).isEmpty)
        let page = try await runner.run(source: "https://open.spotify.com/track/fixture", destination: root, context: context)
        precondition(page.lastPathComponent == "webpage.md")
        let unavailable = DistillRunner(transcriber: runner.transcriber, workDirectory: work)
        do {
            _ = try await unavailable.run(source: "https://example.com/article", destination: root, context: context)
            preconditionFailure("Unconnected webpage saver succeeded")
        } catch {
            precondition(error.localizedDescription.contains("not connected"))
        }
        let fileText = try await runner.transcriber.text(file: result, workDirectory: work, context: context)
        precondition(fileText == "A transcript.\n")
        let ready = AsyncStream<Void>.makeStream()
        let slow = DistillRunner(transcriber: DistillTranscriber { _ in
            ready.continuation.yield(())
            try await Task.sleep(for: .seconds(60))
            return "Late text"
        }, workDirectory: work, saveWebpage: runner.saveWebpage)
        let cancelled = Task {
            try await slow.run(source: "https://youtu.be/cancelled", destination: root.appending(path: "cancelled-output"),
                               context: context)
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

    private static func check(_ condition: @autoclosure () throws -> Bool) rethrows {
        guard try condition() else { preconditionFailure("Distill assertion failed") }
    }

}
