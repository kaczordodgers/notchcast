// notchcast-sources: Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift Tinycast/Platform/ExecutableLocator.swift

import AppKit
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
        let signaled = try await ProcessRunner.run(request("/bin/sh", ["-c", "kill -TERM $$"]))
        check(signaled.signaled && signaled.status == SIGTERM && signaled.exitCode == 128 + SIGTERM)
        let release = Mutex(false)
        var backpressure = request("/usr/bin/perl", ["-e", #"$|=1; print "x" x 2000000;"#])
        backpressure.onData = { _ in
            while !release.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(10)) }
        }
        let blocked = try ProcessRunner.start(backpressure)
        try await Task.sleep(for: .milliseconds(300))
        check(blocked.isRunning)
        release.withLock { $0 = true }
        _ = try await blocked.output()
        let bytes = Mutex(Data())
        let consuming = Mutex(false)
        var binary = request("/usr/bin/perl", ["-e", #"print pack("C*", 0..255) x 256"#])
        binary.groupCleanup = .drainThenKill
        binary.onData = { chunk in
            check(!consuming.withLock { let old = $0; $0 = true; return old })
            try await Task.sleep(for: .milliseconds(300))
            bytes.withLock { $0.append(chunk) }
            consuming.withLock { $0 = false }
        }
        let binaryOutput = try await ProcessRunner.run(binary)
        check(binaryOutput.stdout.isEmpty)
        check(bytes.withLock { $0 } == Data((0..<(256 * 256)).map { UInt8($0 % 256) }))
        final class ConsumerError: Error {}
        let consumerError = ConsumerError()
        let callbacks = Mutex(0)
        binary.arguments = ["-e", #"$|=1; $SIG{INT}=$SIG{TERM}=$SIG{PIPE}="IGNORE"; alarm 4; print "x" x 65536; sleep 30"#]
        binary.stopLadder = .terminating(grace: .milliseconds(100))
        binary.onData = { _ in
            callbacks.withLock { $0 += 1 }
            throw consumerError
        }
        let rejecting = ContinuousClock.now
        let rejected = try ProcessRunner.start(binary)
        check(await failure { try await rejected.output() } as? ConsumerError === consumerError)
        check(rejecting.duration(to: .now) < .seconds(2))
        check(!rejected.isRunning && kill(rejected.processIdentifier, 0) == -1 && errno == ESRCH)
        try await Task.sleep(for: .milliseconds(100))
        check(callbacks.withLock { $0 } == 1)
        print("PASS: binary bytes, serial consumption, backpressure, original consumer error, reaped child, no later callback")

        let lines = Mutex<[String]>([])
        var streaming = request("/usr/bin/perl", ["-e",
            #"$|=1; print "\xc3"; select undef,undef,undef,.05; print "\xa9\r\n\na\rb\n"; sleep 1; print "last";"#])
        streaming.outputTail = 65_536
        streaming.onLine = { line in lines.withLock { $0.append(line) } }
        let streamingRun = try ProcessRunner.start(streaming)
        let deadline = ContinuousClock.now + .seconds(5)
        while lines.withLock({ $0.count < 3 }) {
            check(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        check(streamingRun.isRunning && streamingRun.processIdentifier > 0)
        _ = try await streamingRun.output()
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

        var quit = request("/bin/sleep", ["30"])
        let kept = try ProcessRunner.start(quit)
        quit.killsOnQuit = true
        quit.timeout = .seconds(1)
        let stopped = try ProcessRunner.start(quit)
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        let quitError = await failure { try await stopped.output() }
        let keptRunning = kept.isRunning
        kept.cancel()
        _ = await failure { try await kept.output() }
        check(quitError is CancellationError)
        check(keptRunning)
        print("PASS: shared quit supervision is opt-in and reaps the child")

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
        let drained = try ProcessRunner.start(request("/bin/echo", ["late"]))
        _ = try await drained.output()
        let late = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await drained.output() }
        check((await failure { try await late.value }) is CancellationError)

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
