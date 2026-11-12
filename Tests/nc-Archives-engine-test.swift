// notchcast-sources: Tinycast/Features/Archives/Model/*.swift Tinycast/Features/Archives/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Jobs/JobOutput.swift
// notchcast-kit: platform
import Darwin
import Foundation

@main
struct ArchivesEngineTest {
    struct Locator: ArchiveToolLocating {
        var tool: URL?
        func locate() -> URL? { tool }
    }

    @MainActor static func main() async throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--crash-runner" {
            let root = URL(fileURLWithPath: CommandLine.arguments[2])
            let staging = root.appending(path: "\(ArchiveFiles.stagingPrefix)\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            try Data("crash payload".utf8).write(to: staging.appending(path: "runner-output"))
            try ArchiveRecovery(archive: root.appending(path: "runner.zip"), staging: staging,
                                inPlace: false, state: .finishedExtract).save()
            try Data().write(to: root.appending(path: "runner-ready"))
            while true { try await Task.sleep(for: .seconds(1)) }
        }
        let scratch = ProcessInfo.processInfo.environment["ARCHIVES_TEST_ROOT"]
            .map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        let root = scratch.appending(path: "archives-engine-\(UUID().uuidString)")
        let savedParents = UserDefaults.standard.stringArray(forKey: "archiveRecoveryParents")
        UserDefaults.standard.set([], forKey: "archiveRecoveryParents")
        defer { UserDefaults.standard.set(savedParents, forKey: "archiveRecoveryParents") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? ArchiveFiles.removeStaging(root) }
        try rules()
        try crashRecovery(root)
        try await killedRunner(root)
        try await restoreDefaults()
        let fallbackStage = root.appending(path: "fallback-stage")
        try FileManager.default.createDirectory(at: fallbackStage, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        try Data("safe".utf8).write(to: fallbackStage.appending(path: "payload"))
        let fallbackOutput = try ArchiveFiles.publish(fallbackStage, staging: fallbackStage,
            archive: root.appending(path: "fallback.zip"), exclusiveRename: { _, _ in errno = ENOTSUP; return -1 })
        expect(try Data(contentsOf: fallbackOutput.appending(path: "payload")) == Data("safe".utf8), "ENOTSUP publishes content")
        expect(!fallbackOutput.path.contains("/.notchcast-"), "fallback is visible")
        print("PASS: ENOTSUP exclusive publication preserves visible content")
        let realParent = root.appending(path: "real-parent")
        let aliasParent = root.appending(path: "alias-parent")
        let linkedStage = realParent.appending(path: "stage/Folder")
        try FileManager.default.createDirectory(at: linkedStage, withIntermediateDirectories: true)
        try Data("linked".utf8).write(to: linkedStage.appending(path: "file"))
        try FileManager.default.createSymbolicLink(atPath: linkedStage.appending(path: "link").path,
                                                 withDestinationPath: "file")
        try FileManager.default.createSymbolicLink(atPath: aliasParent.path, withDestinationPath: realParent.path)
        let prepared = try ArchiveFiles.prepare(aliasParent.appending(path: "stage"), quarantine: nil)
        expect(prepared.lastPathComponent == "Folder", "symlinked parent uses resolved boundary")
        print("PASS: safe relative symlink under symlinked parent")
        try await fakeTool(root)
        try await fakeTool(aliasParent)
        try protectedOrphan(aliasParent)
        try protectedOrphan(ArchiveFiles.resolvedDirectory(realParent))
        print("PASS: archive extraction, cancellation and resume behind a symlinked directory")
        if let tool = ArchiveToolLocator().locate() {
            try await realTool(root, tool: tool)
            print("PASS: installed hatchzip, ZIP/7z/tar/tgz/split ZIP, quarantine, readonly cleanup, exclusive publish")
        } else {
            print("SKIP: installed hatchzip run: hatchzip not installed")
        }
        print("PASS: listing limits, paths, collisions, symlink ancestors, FIFO, cancellation, retry, typed failures")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }

    static func protectedOrphan(_ root: URL) throws {
        let staging = root.appending(path: "\(ArchiveFiles.stagingPrefix)\(UUID().uuidString)")
        let archive = root.appending(path: "movie.zip")
        let journal = URL(fileURLWithPath: archive.path + ".hatchzip")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        let payload = staging.appending(path: "part.bin")
        try Data("partial".utf8).write(to: payload)
        try Data("archive".utf8).write(to: archive)
        let data = try JSONSerialization.data(withJSONObject: ["output": staging.path])
        try data.write(to: journal)
        defer {
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: archive)
            try? FileManager.default.removeItem(at: journal)
        }
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        try ArchiveRecovery.recover(in: root)
        expect(try Data(contentsOf: payload) == Data("partial".utf8), "journal protects partial staging")
        expect(try Data(contentsOf: journal) == data, "orphan journal unchanged")
        expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == before,
               "protected orphan never published")
        print("PASS: journal without JSON sidecar protects partial staging at \(root.path)")
    }

    static func crashRecovery(_ root: URL) throws {
        for state in [ArchiveRecovery.State.running, .finishedExtract, .publishing] {
            let archive = root.appending(path: "crash-\(state.rawValue).zip")
            try Data("source".utf8).write(to: archive)
            let staging = root.appending(path: "\(ArchiveFiles.stagingPrefix)\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
            try Data("payload".utf8).write(to: staging.appending(path: "crash-\(state.rawValue)"))
            var record = ArchiveRecovery(archive: archive, staging: staging, inPlace: false, state: state)
            record.owner = 0
            try record.save()
            if state == .finishedExtract {
                try Data("existing".utf8).write(to: root.appending(path: "crash-\(state.rawValue)"))
            }
            let output = try ArchiveRecovery.recover(in: root, archive: archive)
            expect(!ArchiveFiles.exists(staging) && !ArchiveFiles.exists(record.sidecar), "durable recovery cleaned")
            expect(ArchiveFiles.exists(archive), "recovery preserves keep source")
            expect((output != nil) == (state != .running), "finished crash publishes; running crash cleans")
            if state == .finishedExtract {
                expect(output?.lastPathComponent == "crash-finishedExtract (recovered)", "collision recovers visibly")
            }
        }
        print("PASS: durable running, finished-extract and publishing crash recovery")
        let archive = root.appending(path: "partial.zip")
        try Data("partial archive".utf8).write(to: archive)
        let staging = root.appending(path: "\(ArchiveFiles.stagingPrefix)\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        try Data("partial output".utf8).write(to: staging.appending(path: "partial"))
        var record = ArchiveRecovery(archive: archive, staging: staging, inPlace: true, state: .running)
        record.owner = 0
        try record.save()
        let journal = URL(fileURLWithPath: archive.path + ".hatchzip")
        let data = try JSONSerialization.data(withJSONObject: ["output": staging.path, "total_size": 14,
                                                              "parts": [[archive.path, 15]]])
        try data.write(to: journal)
        let jobs = try ArchiveRecovery.recoverKnown()
        expect(jobs.contains { $0.archive == ArchiveFiles.resolvedParent(archive) && $0.state == .cancelled
            && $0.recovery?.staging == ArchiveFiles.resolvedParent(staging)
            && $0.mode == .inPlace }, "in-place marked resumable")
        expect(try Data(contentsOf: journal) == data, "journal unchanged")
        expect(try String(contentsOf: archive, encoding: .utf8) == "partial archive", "partial archive unchanged")
        expect(ArchiveFiles.exists(staging.appending(path: "partial")), "partial staging preserved")
        for empty in [true, false] {
            let orphan = root.appending(path: "\(ArchiveFiles.stagingPrefix)\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: false)
            if !empty { try Data("orphan".utf8).write(to: orphan.appending(path: "orphan-output")) }
            try ArchiveRecovery.recover(in: root)
            expect(!ArchiveFiles.exists(orphan), "orphan staging removed or published")
            if !empty { expect(ArchiveFiles.exists(root.appending(path: "orphan-output")), "orphan output visible") }
        }
        try FileManager.default.removeItem(at: journal)
        try ArchiveFiles.removeStaging(staging)
        try record.remove()
        print("PASS: unfinished in-place stays resumable; nonempty and empty orphans recovered")
    }

    @MainActor static func killedRunner(_ root: URL) async throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        child.arguments = ["--crash-runner", root.path]
        let exit = try child.runObservingExit()
        defer { if child.isRunning { kill(child.processIdentifier, SIGKILL) } }
        while !ArchiveFiles.exists(root.appending(path: "runner-ready")) {
            guard child.isRunning else { fatalError("runner not ready") }
            try await Task.sleep(for: .milliseconds(20))
        }
        kill(child.processIdentifier, SIGKILL)
        exit.wait()
        expect(child.terminationReason == .uncaughtSignal && child.terminationStatus == SIGKILL, "runner killed")
        try ArchiveRecovery.recover(in: root)
        expect(try String(contentsOf: root.appending(path: "runner-output"), encoding: .utf8) == "crash payload",
               "SIGKILL of app-side runner recovers visibly")
        print("PASS: SIGKILL of app-side runner publishes durable output visibly")
    }

    @MainActor static func restoreDefaults() async throws {
        let application = URL(fileURLWithPath: "/Applications/Fixture.app")
        let types = Array(ArchiveFormat.typeIdentifiers.prefix(4))
        var attempted: [String] = []
        try await ArchiveDefaultApplicationService.apply(
            enabled: true, application: application, supported: Set(ArchiveFormat.typeIdentifiers), current: { _ in nil }
        ) { attempted.append($0) }
        expect(attempted == ArchiveFormat.defaultTypeIdentifiers, "claims only eligible archive types")
        expect(!attempted.contains("public.iso-image"), "ISO never claimed by real default-service path")
        expect(!attempted.contains("com.apple.installer-package-archive"), "PKG never claimed by real default-service path")
        attempted = []
        do {
            try await ArchiveDefaultApplicationService.apply(
                enabled: false, application: application, supported: Set(types.prefix(3)),
                current: { $0 == types[2] ? URL(fileURLWithPath: "/Applications/Other.app") : application }
            ) { identifier in
                attempted.append(identifier)
                throw ArchiveFailure.filesystem("failure-\(identifier)")
            }
            fatalError("restore errors lost")
        } catch {
            expect(attempted == Array(types.prefix(2)), "restore filters unsupported and other-app types")
            let message = String(describing: error)
            expect(attempted.allSatisfy { message.contains("failure-\($0)") }, "restore collects each type error")
        }
        print("PASS: fake default application service filters restore types and collects per-type errors")
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
        expect(ArchiveFormat.accepts(URL(fileURLWithPath: "plain.gz")), "plain gzip supported")
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
        let comma = try listing([("file, 1 B uncompressed, tail", false)])
        expect(comma.entries.first?.path == "file, 1 B uncompressed, tail", "comma filename parsed")
        var excessive = ArchiveListing()
        refuses(.tooManyEntries) {
            for _ in 0...100_000 { try excessive.feed(Data("       1 B  x\n".utf8)) }
        }
        var invalid = ArchiveListing()
        refuses(.invalidListing) { try invalid.feed(Data("unexpected format\n".utf8)) }
    }

    @MainActor static func wait(_ queue: ArchiveQueue) async throws {
        while queue.jobs.contains(where: { [.queued, .preflighting, .extracting, .cancelling].contains($0.state) }) {
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
            if archive.name == 'unsafe-list.zip': sys.exit(1)
            print('       4 B  result/file.txt')
            print('1 entry, 4 B uncompressed, 100 B zip archive')
        elif args[0] == 'check':
            if archive.name == 'space.zip': sys.exit(3)
            if archive.name == 'password.zip': sys.exit(5)
            if archive.name == 'damaged.zip': sys.exit(4)
            if archive.name == 'solid.rar' and '--keep-archive' not in args: sys.exit(1)
        elif args[0] == 'extract':
            output = pathlib.Path(args[args.index('-o') + 1])
            (output / 'result').mkdir(exist_ok=True)
            (output / 'result/file.txt').write_text('test')
            for _ in range(1500 if archive.name == 'twin.zip' else 0):
                if (archive.parent / 'twin-release').exists(): break
                time.sleep(0.02)
            if archive.name == 'slow.zip':
                signal.signal(signal.SIGINT, signal.SIG_IGN)
                pathlib.Path(str(archive) + '.hatchzip').write_text(json.dumps({'keep': True, 'output': str(output)}))
                time.sleep(30)
            if archive.name == 'failed.zip': sys.exit(1)
            if archive.name in ('finalize.zip', 'post-fail.zip'):
                archive.unlink()
                if archive.name == 'post-fail.zip': os.symlink('/outside', output / 'result/bad')
            if archive.name == 'resume.zip':
                journal = pathlib.Path(str(archive) + '.hatchzip')
                if journal.exists():
                    journal.unlink()
                    archive.unlink()
                else:
                    assert '-y' in args and '--keep-archive' not in args
                    assert args[args.index('--keep-free') + 1] == '2GB'
                    archive.write_text('partial')
                    journal.write_text(json.dumps({'output': str(output), 'total_size': 4, 'parts': [[str(archive), 7]]}))
                    signal.signal(signal.SIGINT, signal.SIG_IGN)
                    time.sleep(30)
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
        expect(queue.jobs[1].output?.lastPathComponent == "result (2)", "exclusive numbering")
        expect(queue.jobs[2].failure == .insufficientSpace, "space typed")
        expect(queue.jobs[3].failure == .passwordRequired, "password typed")
        expect(queue.jobs[4].failure == .damagedArchive, "damaged typed")
        expect(queue.jobs[5].failure == .toolFailed(1), "exit typed")
        let calls = try String(contentsOf: root.appending(path: "calls"), encoding: .utf8)
        expect(calls.hasPrefix("list first.zip\ncheck first.zip\nextract first.zip\nlist second.zip"), "FIFO tool calls")
        let slow = root.appending(path: "slow.zip")
        try Data("archive".utf8).write(to: slow)
        let id = queue.enqueue(slow)
        while !ArchiveFiles.exists(URL(fileURLWithPath: slow.path + ".hatchzip")) {
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
            .allSatisfy { !$0.hasPrefix(ArchiveFiles.stagingPrefix) }, "staging cleaned")
        for name in ["barrier.zip", "later.zip"] {
            let archive = root.appending(path: name)
            try Data("archive".utf8).write(to: archive)
            queue.enqueue(archive)
        }
        queue.retry(queue.jobs[5].id)
        try await wait(queue)
        expect(queue.jobs[5].failure == .toolFailed(1), "retry reexecutes")
        let retriedCalls = try String(contentsOf: root.appending(path: "calls"), encoding: .utf8)
        expect(retriedCalls.contains("extract later.zip\nlist failed.zip\n"), "retry joins FIFO tail")
        let missing = ArchiveQueue(runner: ArchiveExtractionRunner(locator: Locator(tool: nil)))
        missing.enqueue(slow)
        try await wait(missing)
        expect(missing.jobs[0].failure == .toolMissing, "missing tool typed")
        try await inPlace(root, tool: tool)
        let unsafeListing = root.appending(path: "unsafe-list.zip")
        try Data("source".utf8).write(to: unsafeListing)
        do {
            _ = try await ArchiveExtractionRunner(locator: Locator(tool: tool)).extract(unsafeListing)
            fatalError("unsafe listing accepted")
        } catch {
            expect(error as? ArchiveFailure == .unsafePath("unsafe-list.zip"), "listing exit 1 is unsafe")
        }
        let early = root.appending(path: "early.zip")
        try Data("source".utf8).write(to: early)
        var earlyStaging: URL?
        let earlyTask = Task {
            try await ArchiveExtractionRunner(locator: Locator(tool: tool)).extract(early, mode: .inPlace) { update in
                earlyStaging = update.recovery.staging
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do { _ = try await earlyTask.value; fatalError("early cancellation ignored") } catch is CancellationError {}
        guard let earlyStaging else { fatalError("early staging not reported") }
        expect(!ArchiveFiles.exists(earlyStaging), "early in-place cancel cleans empty staging")
        let staleArchive = root.appending(path: "stale.zip")
        try Data("archive".utf8).write(to: staleArchive)
        let staleStage = root.appending(path: "\(ArchiveFiles.stagingPrefix)\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staleStage, withIntermediateDirectories: false)
        let staleJournal: [String: Any] = ["keep": true, "output": staleStage.path,
                                         "total_size": 4, "parts": [[staleArchive.path, 7]]]
        try JSONSerialization.data(withJSONObject: staleJournal).write(to: URL(fileURLWithPath: staleArchive.path + ".hatchzip"))
        let restarted = try await ArchiveExtractionRunner(locator: Locator(tool: tool)).extract(staleArchive)
        expect(ArchiveFiles.exists(restarted) && !ArchiveFiles.exists(staleStage), "stale keep job restarts")
        print("PASS: stale keep journal cleaned and archive reopened")
        let twin = root.appending(path: "twin.zip")
        try Data("archive".utf8).write(to: twin)
        let twinRunner = ArchiveExtractionRunner(locator: Locator(tool: tool))
        async let one = twinRunner.extract(twin)
        async let two = twinRunner.extract(twin)
        func twinCalls(_ step: String) -> Int {
            let calls = (try? String(contentsOf: root.appending(path: "calls"), encoding: .utf8)) ?? ""
            return calls.components(separatedBy: step + " twin.zip\n").count - 1
        }
        while ArchiveExtractionGate.waiting == 0 || twinCalls("extract") == 0 {
            expect(twinCalls("list") < 2, "two extractions ran the tool at once")
            try await Task.sleep(for: .milliseconds(20))
        }
        expect(twinCalls("list") == 1, "the second extraction waits while the first holds the tool")
        try Data().write(to: root.appending(path: "twin-release"))
        expect(Set(try await [one, two]).count == 2, "the same archive extracted twice publishes twice")
        let twinCalls = try String(contentsOf: root.appending(path: "calls"), encoding: .utf8)
        let turn = "list twin.zip\ncheck twin.zip\nextract twin.zip\n"
        expect(twinCalls.hasSuffix(turn + turn), "concurrent extractions take turns")
        try await ArchiveExtractionGate.enter()
        let waiter = Task { try await ArchiveExtractionGate.enter() }
        while ArchiveExtractionGate.waiting == 0 { await Task.yield() }
        waiter.cancel()
        expect(ArchiveExtractionGate.waiting == 0, "a cancelled waiter leaves the line")
        do { try await waiter.value; fatalError("cancelled waiter entered") } catch is CancellationError {}
        ArchiveExtractionGate.leave()
        try await ArchiveExtractionGate.enter()
        ArchiveExtractionGate.leave()
        print("PASS: extractions take turns and a cancelled waiter gives up its place")
    }

    @MainActor static func inPlace(_ root: URL, tool: URL) async throws {
        let queue = ArchiveQueue(runner: ArchiveExtractionRunner(locator: Locator(tool: tool)))
        let solid = root.appending(path: "solid.rar")
        try Data("archive".utf8).write(to: solid)
        queue.enqueue(solid, mode: .inPlace)
        try await wait(queue)
        expect(queue.jobs[0].effectiveMode == .keepArchive, "solid fallback mode")
        expect(queue.jobs[0].fallback == .inPlaceCheckRefused(1), "fallback reason retained")
        expect(ArchiveFiles.exists(solid), "solid source preserved")
        let archive = root.appending(path: "resume.zip")
        try Data("archive".utf8).write(to: archive)
        let id = queue.enqueue(archive, mode: .inPlace)
        let journal = URL(fileURLWithPath: archive.path + ".hatchzip")
        while !ArchiveFiles.exists(journal) {
            try await Task.sleep(for: .milliseconds(50))
        }
        queue.cancel(id)
        try await wait(queue)
        expect(queue.jobs[1].state == .cancelled, "in-place cancelled")
        expect(ArchiveFiles.exists(journal), "in-place journal retained")
        expect(try String(contentsOf: archive, encoding: .utf8) == "partial", "partial source retained")
        guard let stage = queue.jobs[1].recovery?.staging else { fatalError("recovery missing") }
        expect(ArchiveFiles.exists(stage.appending(path: "result/file.txt")), "in-place staging retained")
        let defaultQueue = ArchiveQueue(runner: ArchiveExtractionRunner(locator: Locator(tool: tool)))
        defaultQueue.enqueue(archive)
        try await wait(defaultQueue)
        expect(defaultQueue.jobs[0].failure == .existingProgress, "default mode never grants destructive resume")
        queue.retry(id)
        try await wait(queue)
        expect(queue.jobs[1].state == .finished, "in-place retry resumes: \(String(describing: queue.jobs[1].failure))")
        expect(queue.jobs[1].output != nil, "in-place result published")
        expect(!ArchiveFiles.exists(journal), "resume completes journal cleanup")
        let calls = try String(contentsOf: root.appending(path: "calls"), encoding: .utf8)
        expect(calls.components(separatedBy: "list resume.zip\n").count == 2, "resume skips truncated archive preflight")
        expect(!ArchiveFiles.exists(stage), "resume reuses original staging")
        let completed = root.appending(path: "finalize.zip")
        try Data("archive".utf8).write(to: completed)
        let runner = ArchiveExtractionRunner(locator: Locator(tool: tool))
        let publication = Task {
            try await runner.extract(completed, mode: .inPlace) { update in
                if update.recovery.readyToPublish { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        let published = try await publication.value
        expect(ArchiveFiles.exists(published), "late cancellation still publishes consumed archive")
        let failed = root.appending(path: "post-fail.zip")
        try Data("archive".utf8).write(to: failed)
        queue.enqueue(failed, mode: .inPlace)
        try await wait(queue)
        guard let recovered = queue.jobs.last?.output else { fatalError("visible recovery missing") }
        expect(queue.jobs.last?.state == .finished && ArchiveFiles.exists(recovered), "consumed archive recovered visibly")
        expect(!recovered.lastPathComponent.hasPrefix("."), "recovered folder is visible")
        expect(try ArchiveFiles.attributes(recovered).st_mode & 0o777 == 0o755, "normal staging permissions")
        print("PASS: in-place cancellation/resume, keep fallback, late cancellation, visible recovery")
    }

    @MainActor static func realTool(_ root: URL, tool: URL) async throws {
        let script = #"""
        import pathlib, stat, sys, tarfile, zipfile
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
        raw = (root / 'one.zip').read_bytes()
        for index, start in enumerate(range(0, len(raw), 40), 1):
            (root / f'split.zip.{index:03}').write_bytes(raw[start:start+40])
        with zipfile.ZipFile(root / 'badlink.zip', 'w') as archive:
            link = zipfile.ZipInfo('outside')
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(link, '../outside')
        with tarfile.open(root / 'readonly.tar', 'w') as archive:
            directory = tarfile.TarInfo('ReadOnly/')
            directory.type = tarfile.DIRTYPE
            directory.mode = 0o500
            archive.addfile(directory)
            info = archive.gettarinfo(root / 'source.txt', arcname='ReadOnly/content.txt')
            info.mode = 0o400
            with (root / 'source.txt').open('rb') as file: archive.addfile(info, file)
        """#
        let generation = try await ArchiveProcess.run(
            tool: URL(fileURLWithPath: "/usr/bin/python3"), arguments: ["-c", script, root.path])
        try ArchiveProcess.validate(generation.status)
        let sevenZip = try await ArchiveProcess.run(tool: URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["--format", "7zip", "-cf", root.appending(path: "real.7z").path, "-C", root.path, "source.txt"])
        try ArchiveProcess.validate(sevenZip.status)
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
        expect(again.lastPathComponent == "Bundle (2)", "real exclusive collision")
        for name in ["one.zip", "real.tar", "real.tgz", "real.7z", "split.zip.001", "readonly.tar"] {
            let result = try await runner.extract(root.appending(path: name))
            expect(ArchiveFiles.exists(result), "real \(name)")
        }
        let destructive = root.appending(path: "one.zip")
        let result = try await runner.extract(destructive, mode: .inPlace)
        expect(ArchiveFiles.exists(result), "real in-place output")
        expect(!ArchiveFiles.exists(destructive), "real in-place source consumed")
        try await realResume(root, runner: runner, tool: tool)
        for name in ["unsafe.zip", "collision.zip", "badlink.zip"] {
            do {
                _ = try await runner.extract(root.appending(path: name), mode: .inPlace)
                fatalError("unsafe extraction succeeded")
            } catch is ArchiveFailure {}
            expect(ArchiveFiles.exists(root.appending(path: name)), "unsafe in-place source preserved")
        }
        expect(!ArchiveFiles.exists(root.appending(path: "escaped.txt")), "no path escape")
    }

    @MainActor static func realResume(_ root: URL, runner: ArchiveExtractionRunner, tool: URL) async throws {
        let archive = root.appending(path: "real-resume.zip")
        let staging = root.appending(path: "\(ArchiveFiles.stagingPrefix)\(UUID().uuidString)")
        let script = #"""
        import pathlib, signal, subprocess, sys, time, zipfile
        tool, source, output = sys.argv[1:]
        archive = pathlib.Path(source)
        with zipfile.ZipFile(archive, 'w') as file:
            for index in range(2000): file.writestr(f'resumed/{index:04}.bin', b'x' * 32768)
        pathlib.Path(output).mkdir(mode=0o700)
        child = subprocess.Popen([tool, 'extract', '-y', '-q', '--keep-free', '2GB', '-o', output, source],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        journal = pathlib.Path(source + '.hatchzip')
        while child.poll() is None:
            if journal.exists():
                child.send_signal(signal.SIGKILL)
                break
            time.sleep(.001)
        status = child.wait()
        assert status == -9 and journal.exists(), 'real extraction was not killed'
        """#
        let pause = try await ArchiveProcess.run(tool: URL(fileURLWithPath: "/usr/bin/python3"),
                                               arguments: ["-c", script, tool.path, archive.path, staging.path])
        try ArchiveProcess.validate(pause.status)
        let parsed = try ArchiveJournal.read(archive)
        expect(parsed?.mode == .inPlace, "real journal parsed")
        expect(parsed?.recovery.staging == ArchiveFiles.resolvedParent(staging), "real journal destination")
        let output = try await runner.extract(archive, mode: .inPlace)
        let file = output.appending(path: "0000.bin")
        expect(try Data(contentsOf: file) == Data(repeating: 120, count: 32768), "real resumed bytes")
        expect(try FileManager.default.contentsOfDirectory(atPath: output.path).count == 2000, "all resumed entries")
        expect(!ArchiveFiles.exists(URL(fileURLWithPath: archive.path + ".hatchzip")), "real resume journal removed")
        expect(!ArchiveFiles.exists(staging), "real resume staging published")
        print("PASS: interrupted installed hatchzip and resumed its original journal with the engine")
    }
}
