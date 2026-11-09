// notchcast-sources: Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift Tinycast/Platform/ExecutableLocator.swift

import Darwin
import Foundation

@main
struct ProcessRunnerTest {
    static func request(_ path: String, _ arguments: [String] = []) -> ProcessRunner.Request {
        .init(executable: URL(filePath: path), arguments: arguments)
    }

    static func leftovers() -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())) ?? []
        return names.filter { $0.hasPrefix("notchcast-run-") }.count
    }

    @MainActor static func failure(_ operation: () async throws -> some Any) async -> (any Error)? {
        do { _ = try await operation(); return nil } catch { return error }
    }

    static func check(_ condition: Bool, line: UInt = #line) {
        precondition(condition, "check failed at line \(line)")
    }

    @MainActor static func main() async throws {
        let before = leftovers()

        let echo = try await ProcessRunner.run(request("/bin/echo", ["hello"]))
        check(echo.status == 0 && echo.stdout == Data("hello\n".utf8) && echo.stderr.isEmpty)
        check((try await ProcessRunner.run(request("/usr/bin/true"))).status == 0)

        var failing = request("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        failing.stderr = .capture
        let failed = try await ProcessRunner.run(failing)
        check(failed.status == 3)
        check(failed.stdout == Data("out\n".utf8))
        check(failed.stderr == Data("err\n".utf8))
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
        limited.stderr = .capture
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
        interrupted.stopSignal = SIGINT
        interrupted.timeout = .milliseconds(300)
        check(await failure { try await ProcessRunner.run(interrupted) } as? ProcessRunner.Failure == .timedOut)

        let running = Task { try await ProcessRunner.run(request("/bin/sleep", ["30"])) }
        try await Task.sleep(for: .milliseconds(200))
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
        // The strict one-thread pool is held by the blocking run, so a timer task could never wake to cancel it.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { blockedCancel.cancel() }
        check((await failure { try await blockedCancel.value }) is CancellationError)

        // Run through the app's own tool lookup once, the way a caller does.
        let located = await ExecutableLocator.locate("echo")
        check(located != nil)
        let viaLocator = try await ProcessRunner.run(.init(executable: located!, arguments: ["located"],
                                                           environment: ExecutableLocator.environment(running: located!)))
        check(viaLocator.stdout == Data("located\n".utf8))

        check(leftovers() == before)
        print("PASS: success, non-zero exit, stderr modes, stdin, environment, directory, output limit, launch failure")
        print("PASS: timeout, grace kill of a child that ignores TERM, custom stop signal, cancel, pre-cancel")
        print("PASS: blocking entry point success, failure, timeout, cancel; temporary files removed")
    }
}
