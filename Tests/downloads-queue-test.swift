// notchcast-sources: Tinycast/Features/Downloads/Model/*.swift Tinycast/Features/Downloads/Service/*.swift
// notchcast-kit: platform
// notchcast-sources: Tinycast/Platform/AppPaths.swift Tinycast/Platform/ExecutableLocator.swift
import AppKit
import Darwin
import Foundation
import Synchronization

@main
struct DownloadsQueueTest {
    @MainActor
    static func main() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let base = ProcessInfo.processInfo.environment["NOTCHCAST_DOWNLOADS_TEST_ROOT"]
            .map { URL(filePath: $0) } ?? home.appending(path: "agents/downloads-queue-test")
        let root = base.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await concurrencyAndFIFO(root)
        try await actions(root)
        try await persistence(root)
        try await readOnlyJobs(root)
        try await unreadablePersistence(root)
        try await tools(root)
        try await processes(root)
        print("downloads-queue-test: all checks passed")
    }

    @MainActor
    private static func concurrencyAndFIFO(_ root: URL) async throws {
        let probe = Probe()
        let queue = try await DownloadQueue(file: nil, destination: root)
        queue.register(GateRunner(probe: probe))
        let jobs = queue.enqueue(kind: "fake", sources: (0..<7).map(String.init))
        try await eventually { probe.started.count == 3 }
        expect(Set(probe.started) == Set(["0", "1", "2"]), "first three jobs start")
        expect(queue.jobs.filter { $0.state == .running }.count == 3, "default concurrency is three")
        expect(queue.jobs.suffix(4).allSatisfy { $0.state == .waiting }, "remaining jobs wait")
        probe.released.insert("0")
        try await eventually { probe.started.count == 4 }
        expect(probe.started.last == "3", "oldest waiting job starts next")
        probe.released.formUnion((0..<7).map(String.init))
        try await eventually { queue.jobs.allSatisfy { $0.state == .done } }
        expect(probe.maximum == 3, "runner concurrency never exceeds cap")
        expect(queue.jobs.map(\.id) == jobs.map(\.id), "rows stay ordered newest last")
        expect(queue.jobs.allSatisfy { $0.output?.hasPrefix(root.path) == true }, "runner output retained")
        await queue.stop()

        let serialProbe = Probe()
        let serial = try await DownloadQueue(file: nil, destination: root, maxConcurrent: 1)
        serial.register(GateRunner(probe: serialProbe))
        let unknown = serial.enqueue(kind: "unregistered", sources: ["unknown"])[0]
        expect(serial.jobs.first?.state == .failed && serial.jobs.first?.detail != nil,
               "unregistered runner fails without blocking FIFO")
        serial.remove(unknown.id)
        serial.enqueue(kind: "fake", sources: ["a", "b", "c", "d"])
        for (index, source) in ["a", "b", "c", "d"].enumerated() {
            try await eventually { serialProbe.started.count == index + 1 }
            expect(serialProbe.started.last == source, "FIFO start order")
            serialProbe.released.insert(source)
        }
        try await eventually { serial.jobs.allSatisfy { $0.state == .done } }
        await serial.stop()
    }

    @MainActor
    private static func actions(_ root: URL) async throws {
        let probe = Probe()
        let queue = try await DownloadQueue(file: nil, destination: root, maxConcurrent: 1)
        queue.register(GateRunner(probe: probe))
        let added = queue.enqueue(kind: "fake", sources: ["first", "second", "third"],
                                  options: ["format": "mp3"], group: "batch")
        try await eventually { probe.started.count == 1 }
        queue.cancel(added[1].id)
        expect(queue.jobs[1].state == .cancelled, "cancel waiting job")
        queue.cancel(added[0].id)
        queue.retry(added[0].id)
        expect(queue.jobs.last?.id == added[0].id, "retry moves same id to FIFO tail")
        expect(queue.jobs.last?.options == added[0].options && queue.jobs.last?.group == "batch", "retry retains input")
        try await eventually { probe.started.contains("third") }
        expect(!probe.started.contains("second"), "cancelled waiting runner never starts")
        probe.released.formUnion(["first", "third"])
        try await eventually { queue.jobs.filter { $0.state == .done }.count == 2 }
        expect(queue.jobs.last?.source == "first", "retry retains source")
        expect(queue.jobs.last?.progress?.fraction == 0.5, "runner progress applied")
        queue.clearFinished()
        expect(queue.jobs.isEmpty, "clear removes terminal rows")
        let removed = queue.enqueue(kind: "fake", sources: ["remove", "after"])
        try await eventually { probe.started.contains("remove") }
        queue.remove(removed[0].id)
        try await eventually { probe.started.contains("after") }
        probe.released.insert("after")
        try await eventually { queue.jobs.first?.state == .done }
        expect(queue.jobs.count == 1 && queue.jobs[0].source == "after", "remove running job rejects stale completion")
        await queue.stop()
    }

    @MainActor
    private static func persistence(_ root: URL) async throws {
        let file = root.appending(path: "storage/downloads.json")
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let states: [DownloadState] = [.running, .waiting, .done, .failed, .cancelled, .interrupted]
        var rows = states.enumerated().map { index, state in
            DownloadJob(id: UUID().uuidString, kind: "fake", source: "row-\(index)", title: "Title",
                        group: "batch", state: state, progress: DownloadProgress(fraction: 0.2),
                        detail: "status", created: now.addingTimeInterval(-9 * 86400),
                        finished: state.isFinished ? now.addingTimeInterval(-86400) : nil,
                        options: ["format": "test"])
        }
        for state in [DownloadState.done, .failed, .cancelled, .interrupted] {
            var row = rows[2]
            row.id = UUID().uuidString
            row.state = state
            row.finished = now.addingTimeInterval(-7 * 86400)
            rows.append(row)
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(rows).write(to: file, options: .atomic)
        let queue = try await DownloadQueue(file: file, destination: root, clock: { now })
        expect(queue.jobs.count == 6, "seven-day terminal expiry")
        expect(queue.jobs[0].state == .interrupted && queue.jobs[0].finished == now, "running reload becomes interrupted")
        expect(queue.jobs[1].state == .waiting, "old waiting job survives expiry")
        queue.register(OtherRunner())
        expect(queue.jobs[1].state == .waiting, "restored job waits for its own runner")
        expect(queue.jobs[2].created == rows[2].created, "expiry uses finish date")
        let stored = try JSONDecoder().decode([DownloadJob].self, from: Data(contentsOf: file))
        expect(stored == queue.jobs, "recovery persisted atomically")
        queue.enqueue(kind: "later", sources: ["one", "two"], options: ["setting": "value"], group: "new")
        queue.cancel(queue.jobs.last?.id ?? "")
        try await queue.flush()
        let reloaded = try await DownloadQueue(file: file, destination: root, clock: { now })
        expect(reloaded.jobs == queue.jobs, "ordered writes retain latest snapshot")
        await queue.stop()
        await reloaded.stop()
        try await reloaded.flush()
        try Data("invalid".utf8).write(to: file)
        let recovered = try await DownloadQueue(file: file, destination: root)
        expect(recovered.jobs.isEmpty && recovered.persistenceError != nil, "corrupt queue recovers with error")
        try expect(Data(contentsOf: file.appendingPathExtension("bad")) == Data("invalid".utf8),
                   "corrupt file is preserved")
        await recovered.stop()
    }

    @MainActor
    private static func readOnlyJobs(_ root: URL) async throws {
        let file = root.appending(path: "read-only/downloads.json")
        var now = Date(timeIntervalSince1970: 2_000_000_000)
        let queue = try await DownloadQueue(file: file, destination: root, clock: { now })
        queue.enqueue(kind: "unregistered", sources: ["expired"])
        try await queue.flush()
        let original = try Data(contentsOf: file)
        now = now.addingTimeInterval(8 * 86400)
        expect(queue.jobs.count == 1, "reading jobs does not expire rows")
        expect(queue.jobs.count == 1, "repeated reads preserve rows")
        try await queue.flush()
        try expect(Data(contentsOf: file) == original, "reading jobs does not persist changes")
        queue.expireFinished()
        expect(queue.jobs.isEmpty, "expireFinished drops old finished rows on a running app")
        queue.enqueue(kind: "unregistered", sources: ["expired"])
        now = now.addingTimeInterval(8 * 86400)
        queue.enqueue(kind: "unregistered", sources: ["fresh"])
        expect(queue.jobs.map(\.source) == ["fresh"], "enqueue expires old finished rows")
        await queue.stop()
    }

    @MainActor
    private static func unreadablePersistence(_ root: URL) async throws {
        let file = root.appending(path: "unreadable/downloads.json")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let marker = file.appending(path: "preserved")
        try Data("fixture".utf8).write(to: marker)
        let queue = try await DownloadQueue(file: file, destination: root)
        expect(queue.jobs.isEmpty && queue.persistenceError != nil, "unreadable queue starts empty with error")
        try expect(Data(contentsOf: file.appendingPathExtension("bad").appending(path: "preserved"))
                   == Data("fixture".utf8), "unreadable queue is moved aside intact")
        queue.enqueue(kind: "unregistered", sources: ["new"])
        try await queue.flush()
        let rows = try JSONDecoder().decode([DownloadJob].self, from: Data(contentsOf: file))
        expect(rows.map(\.source) == ["new"], "recovered queue persists new jobs")
        await queue.stop()
    }

    @MainActor
    private static func tools(_ root: URL) async throws {
        let first = root.appending(path: "first")
        let second = root.appending(path: "second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let tool = DownloadTool(name: "fixture-tool", installCommand: "brew install fixture-tool")
        try executable(first.appending(path: tool.name), "#!/bin/sh\nprintf 'fixture 1.2\\n'\n")
        try executable(second.appending(path: tool.name), "#!/bin/sh\nprintf 'wrong\\n'\n")
        let lookup = DownloadToolLookup(directories: [first, second], home: root, environment: ["SECRET": "omitted"])
        let reading = try await lookup.lookup(tool)
        expect(reading.path == first.appending(path: tool.name) && reading.version == "fixture 1.2", "lookup path and version")
        expect(lookup.environment["SECRET"] == nil, "unrelated environment is excluded")
        expect(lookup.environment["PATH"] == [first.path, second.path].joined(separator: ":"), "child PATH uses search folders")
        let directories = DownloadToolLookup.searchDirectories(home: root, path: "/custom/bin:/usr/local/bin:/bin:.")
        expect(directories.map(\.path) == ["/opt/homebrew/bin", "/usr/local/bin",
                                          root.appending(path: ".local/bin").path, "/custom/bin", "/bin"], "lookup order")
        let missing = DownloadTool(name: "absent", installCommand: "brew install absent")
        let absent = try await lookup.lookup(missing)
        expect(absent.path == nil && absent.status == "Not installed", "missing tool reading")
        expect(absent.installCommand == "brew install absent", "copyable install command")
        let queue = try await DownloadQueue(file: nil, destination: root, tools: lookup)
        let probe = Probe()
        queue.register(GateRunner(probe: probe, tools: [missing]))
        queue.enqueue(kind: "fake", sources: ["never"])
        try await eventually { queue.jobs.first?.state == .failed }
        expect(probe.started.isEmpty && queue.jobs.first?.detail?.contains(missing.installCommand) == true,
               "missing tool fails before runner with install hint")
        try executable(first.appending(path: missing.name), "#!/bin/sh\nexit 0\n")
        probe.released.insert("never")
        queue.retry(queue.jobs[0].id)
        try await eventually { queue.jobs.first?.state == .done }
        expect(probe.started == ["never"], "retry checks newly installed tools on demand")
        await queue.stop()
        let slow = DownloadTool(name: "slow-tool", installCommand: "install manually")
        try executable(first.appending(path: slow.name), "#!/bin/sh\nexec /bin/sleep 60\n")
        let timeout = try await lookup.lookup(slow, timeout: .milliseconds(50))
        expect(timeout.path != nil && timeout.version == nil, "version probe is bounded")
    }

    @MainActor
    private static func processes(_ root: URL) async throws {
        let context = DownloadRunContext(destination: root)
        let lines = Lines()
        let result = try await context.spawn(executable: URL(filePath: "/bin/sh"), arguments: [
            "-c", "printf 'one\\rtwo\\nlast'; printf 'error one\\nlast error\\n  \\n' >&2"
        ], onLine: { line in lines.value.withLock { $0.append(line) } })
        expect(result.output == "one\rtwo\nlast", "stdout captured")
        expect(result.errors.contains("last error"), "stderr captured")
        expect(lines.value.withLock { $0 } == ["one", "two", "last"], "CR, LF and final partial line reported")
        let large = try await context.spawn(executable: URL(filePath: "/bin/sh"), arguments: ["-c", """
            i=0
            while [ "$i" -lt 4000 ]; do
                printf 'stdout output is streamed\\n'
                printf 'stderr tail stays bounded\\n' >&2
                i=$((i+1))
            done
            """])
        expect(large.output.utf8.count == 65_536 && large.errors.utf8.count == 65_536, "both streams drain with bounded tails")
        let burst = Lines()
        _ = try await context.spawn(executable: URL(filePath: "/usr/bin/seq"), arguments: ["1", "100000"],
                                    onLine: { line in burst.value.withLock { $0.append(line) } })
        expect(burst.value.withLock { $0.count == 100000 && $0.last == "100000" },
               "all output lines drain through EOF after exit")
        do {
            _ = try await context.spawn(executable: URL(filePath: "/bin/sh"), arguments: [
                "-c", "printf 'first\\nlast failure\\n  \\n' >&2; exit 7"
            ])
            fatalError("nonzero child must throw")
        } catch {
            expect(error.localizedDescription == "last failure", "last nonblank stderr line is failure detail")
        }
        for mode in ["cancel", "task", "quit", "stop", "leader-exits"] {
            try await processTree(root.appending(path: mode), mode: mode)
        }
        let task = Task {
            try Task.checkCancellation()
            return try await context.spawn(executable: URL(filePath: "/bin/sleep"), arguments: ["60"])
        }
        task.cancel()
        do {
            _ = try await task.value
            fatalError("pre-cancelled spawn must throw")
        } catch is CancellationError {}
    }

    @MainActor
    private static func processTree(_ root: URL, mode: String) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = root.appending(path: "parent.sh")
        let child = root.appending(path: "child.sh")
        let sleepPID = root.appending(path: "sleep.pid")
        let childPID = root.appending(path: "child.pid")
        let parentPID = root.appending(path: "parent.pid")
        try executable(child, """
        #!/bin/sh
        trap '' TERM
        /bin/sleep 60 &
        echo $! > "$1"
        wait

        """)
        try executable(script, """
        #!/bin/sh
        echo $$ > "$1"
        /bin/sh "$2" "$3" &
        echo $! > "$4"
        \(mode == "leader-exits" ? "trap 'exit 0' TERM" : "trap '' TERM")
        wait

        """)
        let arguments = [script.path, parentPID.path, child.path, sleepPID.path, childPID.path]
        let lookup = DownloadToolLookup()
        let queue = try await DownloadQueue(file: nil, destination: root, tools: lookup)
        queue.register(ProcessRunner(arguments: arguments))
        let job = queue.enqueue(kind: "process", sources: ["fixture"])[0]
        try await eventually { FileManager.default.fileExists(atPath: sleepPID.path) }
        let pids = try [parentPID, childPID, sleepPID].map { file -> pid_t in
            let text = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let pid = pid_t(text) else { throw HarnessError.timeout }
            return pid
        }
        expect(pids.allSatisfy { kill($0, 0) == 0 }, "process tree exists before cancellation")
        if mode == "quit" {
            NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        } else if mode == "stop" {
            await queue.stop()
        } else {
            queue.cancel(job.id)
        }
        try await eventually { pids.allSatisfy { kill($0, 0) == -1 && errno == ESRCH } }
        expect(pids.allSatisfy { kill($0, 0) == -1 && errno == ESRCH }, "leader, child and sleep descendant are gone")
        await queue.stop()
        if mode == "stop" { expect(queue.jobs[0].state == .interrupted, "stop preserves interrupted state") }
    }

    private static func executable(_ file: URL, _ text: String) throws {
        try text.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }

    private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) rethrows {
        if try !value() { fatalError(message) }
    }

    @MainActor
    private static func eventually(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw HarnessError.timeout }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private enum HarnessError: Error { case timeout }

    private final class Lines: Sendable {
        let value = Mutex<[String]>([])
    }

    @MainActor
    private final class Probe {
        var started: [String] = []
        var released = Set<String>()
        var active = 0
        var maximum = 0

        func begin(_ source: String) {
            started.append(source)
            active += 1
            maximum = max(maximum, active)
        }

        func end() { active -= 1 }
    }

    private struct OtherRunner: DownloadRunner {
        let kind = "other"
        var tools: [DownloadTool] = []

        func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? { nil }
    }

    private struct GateRunner: DownloadRunner {
        let kind = "fake"
        let probe: Probe
        var tools: [DownloadTool] = []

        func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
            await probe.begin(job.source)
            do {
                await context.report(DownloadProgress(fraction: 0.5, received: 5, total: 10))
                while await !probe.released.contains(job.source) { try await Task.sleep(for: .milliseconds(5)) }
                try Task.checkCancellation()
                await probe.end()
                return context.destination.appending(path: job.source)
            } catch {
                await probe.end()
                throw error
            }
        }
    }

    private struct ProcessRunner: DownloadRunner {
        let kind = "process"
        let tools: [DownloadTool] = []
        let arguments: [String]

        func run(_ job: DownloadJob, context: DownloadRunContext) async throws -> URL? {
            _ = try await context.spawn(executable: URL(filePath: "/bin/sh"), arguments: arguments)
            return nil
        }
    }
}
