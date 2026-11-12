// notchcast-sources: Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift Tinycast/Platform/ExecutableLocator.swift

import Darwin
import Foundation
import Synchronization

@main
struct ProcessRunnerTest {
    static let marker = Data("process-runner-test \(UUID())".utf8)

    static func request(_ path: String, _ arguments: [String] = []) -> ProcessRunner.Request {
        .init(executable: URL(filePath: path), arguments: arguments, input: marker)
    }

    // Parallel harnesses share the temp folder, so count only runs whose stdin is our marker.
    static func leftovers() -> Int {
        let temp = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []
        return names.filter { name in
            guard name.hasPrefix("notchcast-run-") else { return false }
            return (try? Data(contentsOf: temp.appending(path: "\(name)/in"))) == marker
        }.count
    }

    @MainActor static func failure(_ operation: () async throws -> some Any) async -> (any Error)? {
        do { _ = try await operation(); return nil } catch { return error }
    }

    static func check(_ condition: Bool, line: UInt = #line) {
        precondition(condition, "check failed at line \(line)")
    }

    @MainActor static func main() async throws {
        let lines = Mutex<[String]>([])
        var streaming = request("/usr/bin/perl", ["-e",
            #"$|=1; print "\xc3"; select undef,undef,undef,.05; print "\xa9\r\n\na\rb\n"; sleep 1; print "last";"#])
        streaming.outputTail = 65_536
        streaming.onLine = { line in lines.withLock { $0.append(line) } }
        let running = try ProcessRunner.start(streaming)
        let deadline = ContinuousClock.now + .seconds(5)
        while lines.withLock({ $0.count < 3 }) {
            check(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        check(running.isRunning && running.processIdentifier > 0)
        _ = try await running.output()
        check(lines.withLock { $0 } == ["é", "a", "b", "last"])
        streaming.arguments = ["-e", #"print "x" x 200000; print "END"; print STDERR "y" x 200000, "ERR";"#]
        streaming.stderr = .capture(limit: 65_536)
        streaming.onLine = nil
        let tail = try await ProcessRunner.run(streaming)
        check(tail.stdout.count == 65_536 && tail.stdout.suffix(3) == Data("END".utf8))
        check(tail.stderr.count == 65_536 && tail.stderr.suffix(3) == Data("ERR".utf8))
        print("PASS: incremental split UTF-8, CR/LF/CRLF, final partial line, bounded stdout/stderr")

        let echo = try await ProcessRunner.run(request("/bin/echo", ["hello"]))
        check(echo.status == 0 && echo.stdout == Data("hello\n".utf8) && echo.stderr.isEmpty)
        check((try await ProcessRunner.run(request("/usr/bin/true"))).status == 0)

        var failing = request("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        failing.stderr = .capture(limit: .max)
        let failed = try await ProcessRunner.run(failing)
        check(failed.status == 3)
        check(failed.stdout == Data("out\n".utf8))
        check(failed.stderr == Data("err\n".utf8))
        failing.stderr = .capture(limit: 2)
        check((try await ProcessRunner.run(failing)).stderr == Data("er".utf8))
        failing.stderr = .merge
        let merged = try await ProcessRunner.run(failing)
        check(merged.stdout == Data("out\nerr\n".utf8) && merged.stderr.isEmpty)
        failing.stderr = .discard
        check((try await ProcessRunner.run(failing)).stderr.isEmpty)

        var cat = request("/bin/cat")
        cat.input = Data("piped in".utf8)
        check((try await ProcessRunner.run(cat)).stdout == Data("piped in".utf8))

        var env = request("/usr/bin/env")
        env.environment = ["PROBE": "1"]
        check((try await ProcessRunner.run(env)).stdout == Data("PROBE=1\n".utf8))
        var pwd = request("/bin/pwd")
        pwd.directory = URL(filePath: "/usr")
        check((try await ProcessRunner.run(pwd)).stdout == Data("/usr\n".utf8))

        var limited = request("/bin/echo", ["0123456789"])
        limited.outputLimit = 5
        check(await failure { try await ProcessRunner.run(limited) } as? ProcessRunner.Failure == .outputLimit)
        limited.stderr = .capture(limit: .max)
        limited.arguments = ["-n", "ab"]
        limited.outputLimit = 2
        check((try await ProcessRunner.run(limited)).stdout.count == 2)

        check(await failure { try await ProcessRunner.run(request("/nonexistent/tool")) } != nil)

        var slow = request("/bin/sleep", ["30"])
        slow.timeout = .milliseconds(200)
        let started = ContinuousClock.now
        check(await failure { try await ProcessRunner.run(slow) } as? ProcessRunner.Failure == .timedOut)
        check(ContinuousClock.now - started < .seconds(5))

        // A child that ignores the first signal is killed once the grace period ends.
        var stubborn = request("/usr/bin/perl", ["-e", #"$SIG{TERM}="IGNORE"; print "ready\n"; sleep 30"#])
        stubborn.timeout = .milliseconds(500)
        let stubbornStart = ContinuousClock.now
        check(await failure { try await ProcessRunner.run(stubborn) } as? ProcessRunner.Failure == .timedOut)
        let stubbornTook = ContinuousClock.now - stubbornStart
        check(stubbornTook > .seconds(2) && stubbornTook < .seconds(8))

        var interrupted = request("/bin/sh", ["-c", "trap 'exit 7' INT; sleep 30 & wait"])
        interrupted.stopLadder = .terminating(SIGINT)
        interrupted.timeout = .milliseconds(300)
        check(await failure { try await ProcessRunner.run(interrupted) } as? ProcessRunner.Failure == .timedOut)

        let ladder = ProcessRunner.StopLadder.interrupting(kill: .seconds(3))
        check(ladder.first == SIGINT && ladder.later.map(\.signal) == [SIGTERM, SIGKILL])
        check(ladder.signal(after: .milliseconds(500)) == SIGINT && ladder.signal(after: .seconds(2)) == SIGTERM)
        check(ladder.signal(after: .seconds(4)) == SIGKILL)
        let quick = ProcessRunner.StopLadder.terminating(grace: .milliseconds(250))
        check(quick.first == SIGTERM && quick.later.map(\.after) == [.milliseconds(250)])
        let climbed = Mutex<[Int32]>([])
        ProcessRunner.StopLadder(first: SIGINT, later: [
            .init(signal: SIGTERM, after: .milliseconds(20)), .init(signal: SIGKILL, after: .milliseconds(60)),
        ]).escalate { signal in climbed.withLock { $0.append(signal) } }
        try await Task.sleep(for: .milliseconds(300))
        check(climbed.withLock { $0 } == [SIGTERM, SIGKILL])

        // The leader dies on the stop signal; its child ignores it and must go with the group.
        let pidFile = FileManager.default.temporaryDirectory.appending(path: "process-runner-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: pidFile) }
        let orphaning = #"trap "" TERM; sleep 30 & echo $! > "$0"; trap - TERM; wait"#
        var group = request("/bin/sh", ["-c", orphaning, pidFile.path])
        group.stopsGroup = true
        group.timeout = .milliseconds(300)
        check(await failure { try await ProcessRunner.run(group) } as? ProcessRunner.Failure == .timedOut)
        let written = try String(contentsOf: pidFile, encoding: .utf8)
        let orphan = pid_t(written.trimmingCharacters(in: .whitespacesAndNewlines))!
        var gone = false
        for _ in 0..<200 where !gone {
            gone = kill(orphan, 0) == -1 && errno == ESRCH
            if !gone { try await Task.sleep(for: .milliseconds(10)) }
        }
        check(gone)

        let running = Task { try await ProcessRunner.run(request("/bin/sleep", ["30"])) }
        try await Task.sleep(for: .milliseconds(200))
        check(leftovers() == 1)
        let cancelStart = ContinuousClock.now
        running.cancel()
        do { _ = try await running.value; preconditionFailure("cancel returned output") } catch {
            check(error is CancellationError)
        }
        check(ContinuousClock.now - cancelStart < .seconds(5))
        let cancelled = Task { try await ProcessRunner.run(request("/bin/echo", ["never"])) }
        cancelled.cancel()
        check((await failure { try await cancelled.value }) is CancellationError)

        let blocking = try ProcessRunner.runBlocking(request("/bin/echo", ["sync"]))
        check(blocking.status == 0 && blocking.stdout == Data("sync\n".utf8))
        check(try ProcessRunner.runBlocking(request("/usr/bin/false")).status == 1)
        var blockingSlow = request("/bin/sleep", ["30"])
        blockingSlow.timeout = .milliseconds(200)
        do { _ = try ProcessRunner.runBlocking(blockingSlow); preconditionFailure("no timeout") } catch {
            check(error as? ProcessRunner.Failure == .timedOut)
        }
        let blockedCancel = Task.detached { try ProcessRunner.runBlocking(request("/bin/sleep", ["30"])) }
        // The blocking run holds the strict one-thread pool, so a timer task could never wake.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { blockedCancel.cancel() }
        check((await failure { try await blockedCancel.value }) is CancellationError)

        // Run through the app's own tool lookup once, the way a caller does.
        let located = await ExecutableLocator.locate("echo")
        check(located != nil)
        let viaLocator = try await ProcessRunner.run(.init(executable: located!, arguments: ["located"],
                                                           environment: ExecutableLocator.environment(running: located!),
                                                           input: marker))
        check(viaLocator.stdout == Data("located\n".utf8))

        check(leftovers() == 0)
        print("PASS: success, non-zero exit, stderr modes, stdin, environment, directory, output limit, launch failure")
        print("PASS: timeout, grace kill of a child that ignores TERM, custom stop signal, cancel, pre-cancel")
        print("PASS: a group stop kills a child that outlives its leader")
        print("PASS: one stop ladder names every supervisor's signals and delays, and escalates in order")
        print("PASS: blocking entry point success, failure, timeout, cancel; temporary files removed")
    }
}
