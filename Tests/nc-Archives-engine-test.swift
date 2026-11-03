// notchcast-sources: Tinycast/Features/Archives/Model/*.swift Tinycast/Features/Archives/Service/*.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Darwin
import Foundation

@main
struct ArchivesEngineTest {
    struct Locator: ArchiveToolLocating {
        var tool: URL?
        func locate() -> URL? { tool }
    }

    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appending(path: ".archive-fixtures/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try rules()
        try await fakeTool(root)
        if let tool = ArchiveToolLocator().locate() {
            try await realTool(root, tool: tool)
            print("PASS: installed hatchzip, throwaway ZIP/tar/tgz, quarantine, cleanup, exclusive publish")
        } else {
            print("NOT VERIFIED: hatchzip not installed; engine tested against a fake tool script")
        }
        print("PASS: listing limits, paths, collisions, symlink ancestors, FIFO, cancellation, retry, typed failures")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }

    static func listing(_ entries: [(String, Bool)], total: String = "12 B") throws -> ArchiveListing {
        var result = ArchiveListing()
        let lines = entries.map { "       1 B  " + $0.0 + ($0.1 ? " (symlink)" : "") }
            + ["\(entries.count) entries, \(total) uncompressed, 100 B zip archive"]
        for byte in (lines.joined(separator: "\n") + "\n").utf8 { try result.feed(Data([byte])) }
        try result.finish()
        return result
    }

    static func refuses(_ wanted: ArchiveFailure, _ action: () throws -> Void) {
        do { try action(); fatalError("expected \(wanted)") } catch {
            expect(error as? ArchiveFailure == wanted, "expected \(wanted), got \(error)")
        }
    }

    static func rules() throws {
        for name in ["a.zip", "a.7z", "a.rar", "a.part02.rar", "a.r00", "a.tar", "a.tgz", "a.tar.gz", "a.7z.001"] {
            expect(ArchiveFormat.accepts(URL(fileURLWithPath: name)), "format \(name)")
        }
        expect(!ArchiveFormat.accepts(URL(fileURLWithPath: "plain.gz")), "plain gzip unclaimed")
        expect(ArchiveFormat.baseName(URL(fileURLWithPath: "a.part02.rar")) == "a", "RAR basename")
        expect(ArchiveFormat.baseName(URL(fileURLWithPath: "a.tar.gz.001")) == "a", "split basename")
        for path in ["/etc/test", "../escape", "folder/../escape", "C:/escape", "folder\\escape"] {
            refuses(.unsafePath(path)) { try ArchiveRules.validate(listing([(path, false)]), archiveBytes: 100) }
        }
        for paths in [[("A/x", false), ("a/y", false)], [("x", false), ("x", false)],
                      [("é", false), ("e\u{301}", false)]] {
            refuses(.collision(paths[1].0)) { try ArchiveRules.validate(listing(paths), archiveBytes: 100) }
        }
        refuses(.symlinkAncestor("link/child")) {
            try ArchiveRules.validate(listing([("link/child", false), ("link", true)]), archiveBytes: 100)
        }
        refuses(.expansionLimit) {
            try ArchiveRules.validate(listing([("huge", false)], total: "5.1 GB"), archiveBytes: 1)
        }
        try ArchiveRules.validate(listing([("huge", false)], total: "5 GB"), archiveBytes: 1)
        var excessive = ArchiveListing()
        refuses(.tooManyEntries) {
            for _ in 0...100_000 { try excessive.feed(Data("       1 B  x\n".utf8)) }
        }
        var invalid = ArchiveListing()
        refuses(.invalidListing) { try invalid.feed(Data("unexpected format\n".utf8)) }
    }

    @MainActor static func wait(_ queue: ArchiveQueue) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while queue.jobs.contains(where: { [.queued, .preflighting, .extracting, .cancelling].contains($0.state) }) {
            guard ContinuousClock.now < deadline else { fatalError("queue timed out: \(queue.jobs)") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @MainActor static func fakeTool(_ root: URL) async throws {
        let tool = root.appending(path: "fake-hatchzip")
        let script = #"""
        #!/usr/bin/python3
        import json, os, pathlib, signal, sys, time
        args = sys.argv[1:]
        archive = pathlib.Path(args[-1])
        log = archive.parent / 'calls'
        with log.open('a') as file: file.write(args[0] + ' ' + archive.name + '\n')
        if args[0] == 'list':
            print('       4 B  result/file.txt')
            print('1 entry, 4 B uncompressed, 100 B zip archive')
        elif args[0] == 'check':
            if archive.name == 'space.zip': sys.exit(3)
            if archive.name == 'password.zip': sys.exit(5)
            if archive.name == 'damaged.zip': sys.exit(4)
        elif args[0] == 'extract':
            output = pathlib.Path(args[args.index('-o') + 1])
            (output / 'result').mkdir(exist_ok=True)
            (output / 'result/file.txt').write_text('test')
            if archive.name == 'slow.zip':
                signal.signal(signal.SIGINT, signal.SIG_IGN)
                pathlib.Path(str(archive) + '.hatchzip').write_text(json.dumps({'keep': True, 'output': str(output)}))
                time.sleep(30)
            if archive.name == 'failed.zip': sys.exit(1)
        """#
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: tool.path)
        let queue = ArchiveQueue(runner: ArchiveExtractionRunner(locator: Locator(tool: tool)))
        for name in ["first.zip", "second.zip", "space.zip", "password.zip", "damaged.zip", "failed.zip"] {
            let archive = root.appending(path: name)
            try Data("archive".utf8).write(to: archive)
            queue.enqueue(archive)
        }
        try await wait(queue)
        expect(queue.jobs.map(\.state) == [.finished, .finished, .failed, .failed, .failed, .failed], "FIFO outcomes")
        expect(queue.jobs[0].output?.lastPathComponent == "result", "unwrap")
        expect(queue.jobs[1].output?.lastPathComponent == "result 2", "exclusive numbering")
        expect(queue.jobs[2].failure == .insufficientSpace, "space typed")
        expect(queue.jobs[3].failure == .passwordRequired, "password typed")
        expect(queue.jobs[4].failure == .damagedArchive, "damaged typed")
        expect(queue.jobs[5].failure == .toolFailed(1), "exit typed")
        let calls = try String(contentsOf: root.appending(path: "calls"), encoding: .utf8)
        expect(calls.hasPrefix("list first.zip\ncheck first.zip\nextract first.zip\nlist second.zip"), "FIFO tool calls")
        let slow = root.appending(path: "slow.zip")
        try Data("archive".utf8).write(to: slow)
        let id = queue.enqueue(slow)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !ArchiveFiles.exists(URL(fileURLWithPath: slow.path + ".hatchzip")) {
            guard ContinuousClock.now < deadline else { fatalError("fake child never started") }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(400))
        expect(queue.jobs.last?.bytesWritten == 4, "staging progress")
        let queued = queue.enqueue(root.appending(path: "never.zip"))
        queue.cancel(queued)
        queue.cancel(id)
        try await wait(queue)
        expect(queue.jobs.suffix(2).allSatisfy { $0.state == .cancelled }, "active and pending cancel")
        expect(ArchiveFiles.exists(slow), "cancel preserves archive")
        expect(!ArchiveFiles.exists(URL(fileURLWithPath: slow.path + ".hatchzip")), "keep journal cleaned")
        expect(try FileManager.default.contentsOfDirectory(atPath: root.path)
            .allSatisfy { !$0.hasPrefix(".notchcast-extract-") }, "staging cleaned")
        queue.retry(queue.jobs[5].id)
        try await wait(queue)
        expect(queue.jobs[5].failure == .toolFailed(1), "retry reexecutes")
        let missing = ArchiveQueue(runner: ArchiveExtractionRunner(locator: Locator(tool: nil)))
        missing.enqueue(slow)
        try await wait(missing)
        expect(missing.jobs[0].failure == .toolMissing, "missing tool typed")
    }

    @MainActor static func realTool(_ root: URL, tool: URL) async throws {
        let script = #"""
        import pathlib, sys, tarfile, zipfile
        root = pathlib.Path(sys.argv[1])
        for name, entries in {
            'real.zip': {'Bundle/hello.txt': 'hello', '__MACOSX/._Bundle': 'junk', 'Bundle/._hello.txt': 'junk'},
            'one.zip': {'single.txt': 'hello'},
            'unsafe.zip': {'../escaped.txt': 'unsafe'},
            'collision.zip': {'A.txt': 'a', 'a.txt': 'b'}
        }.items():
            with zipfile.ZipFile(root / name, 'w') as archive:
                for path, value in entries.items(): archive.writestr(path, value)
        (root / 'source.txt').write_text('tar content')
        for name, mode in [('real.tar', 'w'), ('real.tgz', 'w:gz')]:
            with tarfile.open(root / name, mode) as archive: archive.add(root / 'source.txt', arcname='tar/file.txt')
        """#
        let generation = try await ArchiveProcess.run(
            tool: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", script, root.path])
        try ArchiveProcess.validate(generation.status)
        let archive = root.appending(path: "real.zip")
        let warning = Data("0081;00000000;ArchivesHarness;".utf8)
        let status = warning.withUnsafeBytes {
            setxattr(archive.path, "com.apple.quarantine", $0.baseAddress, warning.count, 0, XATTR_NOFOLLOW)
        }
        expect(status == 0, "fixture quarantine")
        let runner = ArchiveExtractionRunner(locator: Locator(tool: tool))
        let output = try await runner.extract(archive)
        expect(output.lastPathComponent == "Bundle", "real unwrap")
        expect(try String(contentsOf: output.appending(path: "hello.txt"), encoding: .utf8) == "hello", "real content")
        expect(try ArchiveFiles.quarantine(output.appending(path: "hello.txt")) == warning, "quarantine copied")
        expect(try ArchiveFiles.quarantine(output) == warning, "folder quarantine copied")
        expect(!ArchiveFiles.exists(output.appending(path: "._hello.txt")), "paired metadata removed")
        expect(ArchiveFiles.exists(archive), "archive kept")
        let again = try await runner.extract(archive)
        expect(again.lastPathComponent == "Bundle 2", "real exclusive collision")
        for name in ["one.zip", "real.tar", "real.tgz"] {
            let result = try await runner.extract(root.appending(path: name))
            expect(ArchiveFiles.exists(result), "real \(name)")
        }
        for name in ["unsafe.zip", "collision.zip"] {
            do {
                _ = try await runner.extract(root.appending(path: name))
                fatalError("unsafe extraction succeeded")
            } catch is ArchiveFailure {}
        }
        expect(!ArchiveFiles.exists(root.appending(path: "escaped.txt")), "no path escape")
    }
}
