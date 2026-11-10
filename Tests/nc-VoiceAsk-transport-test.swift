// notchcast-sources: Tinycast/Features/VoiceAsk/Model/*.swift
// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskModule.swift
// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskCLI*.swift
// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskProcessRunner.swift
// notchcast-kit: platform
// notchcast-sources: Tinycast/Platform/ExecutableLocator.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift

import Foundation
import Darwin

enum DialogTone { case success, danger }

@main
struct VoiceAskTransportTest {
    @MainActor final class Fixture {
        var launches = 0
        var status: Int32 = 0
        var text = VoiceAskTransportTest.completed
        var gate: CheckedContinuation<Void, Never>?
        var delay = false
        var stderr = Data()
    }
    static let completed = #"""
    {"threadId":"thread-7f3c2a","runId":"run-4d2e81","status":"completed",
    "reply":"Done. The build is green and the PR is open.","error":null}
    """#
    static let failed = #"""
    {"threadId":"thread-7f3c2a","runId":"run-4d2e81","status":"failed",
    "reply":null,"error":"Provider returned an error: rate limited."}
    """#
    static let waiting = #"""
    {"threadId":"thread-7f3c2a","runId":"run-4d2e81","status":"waiting","reply":null,"error":null}
    """#

    @MainActor static func expect(_ error: VoiceAskCLIError, line: UInt = #line,
                                  _ operation: () async throws -> Void) async throws {
        FileHandle.standardError.write(Data("EXPECT at line \(line): \(error)\n".utf8))
        do {
            try await operation()
            preconditionFailure("Expected an error at line \(line)")
        } catch let actual as VoiceAskCLIError {
            precondition(actual.localizedDescription == error.localizedDescription)
        }
    }

    @MainActor static func main() async throws {
        let fixture = Fixture()
        let transport = VoiceAskCLITransport(resolve: { URL(filePath: "/fake/t3") }, run: { executable, arguments, input in
            fixture.launches += 1
            precondition(executable.path == "/fake/t3")
            precondition(arguments == ["thread", "send", "--wait", "--json", "fixture", "-"])
            precondition(input == Data("private spoken text\nsecond line".utf8))
            if fixture.delay { await withCheckedContinuation { fixture.gate = $0 } }
            return .init(status: fixture.status, stdout: Data(fixture.text.utf8), stderr: fixture.stderr)
        })
        let text = "private spoken text\nsecond line"
        let reply = try await transport.send(text, destination: "fixture")
        precondition(reply == .init(state: .completed, firstLines: ["Done. The build is green and the PR is open."]))
        fixture.status = 1
        fixture.text = failed
        let failure = try await transport.send(text, destination: "fixture")
        precondition(failure == .init(state: .failed, firstLines: ["Provider returned an error: rate limited."]))
        let unsanitized = VoiceAskCLITransport(resolve: { URL(filePath: "/fake/t3") }, run: { _, _, input in
            precondition(input == Data("error".utf8))
            return .init(status: 1, stdout: Data(failed.utf8))
        })
        let intactFailure = try await unsanitized.send("error", destination: "fixture")
        precondition(intactFailure == failure)
        fixture.status = 2
        fixture.text = #"{"status":"failed","error":"No such thread","reply":null}"#
        let missingThread = try await transport.send(text, destination: "fixture")
        precondition(missingThread == .init(state: .failed, firstLines: ["No such thread"]))
        fixture.status = 1
        print("PASS: utterance error preserves diagnostic; exit 2 failed JSON reports No such thread")
        for output in ["", #"{"status":"interrupted","error":null,"reply":null}"#] {
            fixture.text = output
            fixture.stderr = Data("Server stopped".utf8)
            let stopped = try await transport.send(text, destination: "fixture")
            precondition(stopped == .init(state: .failed, firstLines: ["The T3 run stopped.", "Server stopped"]))
        }
        fixture.stderr = Data()
        print("PASS: exit 1 without JSON and with null error report stopped run and stderr")
        fixture.status = 2
        fixture.text = waiting
        let pending = try await transport.send(text, destination: "fixture")
        precondition(pending.state == .running && pending.firstLines == ["The agent is waiting for an answer in T3 Code."])
        fixture.status = 0
        let pendingAtZero = try await transport.send(text, destination: "fixture")
        precondition(pendingAtZero == pending)
        fixture.text = "not JSON"
        try await expect(.invalidOutput) { _ = try await transport.send(text, destination: "fixture") }
        for destination in ["", "has space", "line\nbreak", "--help"] {
            try await expect(.invalidDestination) { _ = try await transport.send(text, destination: destination) }
        }
        let missing = VoiceAskCLITransport(resolve: { nil }, run: { _, _, _ in preconditionFailure("Must not launch") })
        try await expect(.missingCLI) { _ = try await missing.send(text, destination: "fixture") }
        let timed = VoiceAskCLITransport(resolve: { URL(filePath: "/fake/t3") }, run: { _, _, _ in
            throw VoiceAskCLIError.timeout
        })
        try await expect(.timeout) { _ = try await timed.send(text, destination: "fixture") }
        let suite = "voice-transport-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var messages: [(String, DialogTone)] = []
        var recordings = 0
        let module = VoiceAskModule(defaults: defaults, begin: { recordings += 1 }, finish: { text }, cancel: {},
                                    message: { messages.append(($0, $1)) })
        module.destination = "fixture"
        module.configure(transport: transport)
        let before = fixture.launches
        module.press(alone: true)
        try await Task.sleep(for: .milliseconds(300))
        module.release()
        precondition(fixture.launches == before)
        module.start()
        for (status, output, expected, danger) in [
            (Int32(0), completed, "Done. The build is green and the PR is open.", false),
            (Int32(1), failed, "Provider returned an error: rate limited.", true),
            (Int32(2), waiting, String(localized: "The agent is waiting for an answer in T3 Code."), false),
            (Int32(0), "not JSON", VoiceAskCLIError.invalidOutput.localizedDescription, true)
        ] {
            fixture.status = status
            fixture.text = output
            let count = messages.count
            module.press(alone: true)
            try await wait { recordings > count }
            module.release()
            try await wait { messages.count == count + 1 }
            precondition(messages.last!.0 == expected)
            precondition(messages.last!.1 == (danger ? .danger : .success))
        }
        print("PASS: reply delivered once, failed reply and thrown error use danger, waiting uses localized status")
        fixture.delay = true
        fixture.text = completed
        for action in 0..<3 {
            module.destination = "fixture"
            module.start()
            let previous = recordings
            module.press(alone: true)
            try await wait { recordings > previous }
            module.release()
            try await wait { fixture.gate != nil }
            if action == 0 { module.destination = "changed" }
            if action == 1 { module.stop() }
            if action == 2 { module.configure(transport: nil) }
            fixture.gate?.resume()
            fixture.gate = nil
            try await Task.sleep(for: .milliseconds(50))
            precondition(messages.count == 4)
        }
        print("PASS: destination change, switch off and cancellation suppress message sink")
        print("PASS: exact argv and stdin, three CLI fixtures, waiting status, off means no launch")
        print("PASS: invalid destination, missing CLI, bad JSON, timeout")
        let echoed = try await VoiceAskProcessRunner.run(URL(filePath: "/bin/cat"), arguments: [], input: Data(text.utf8))
        precondition(echoed.status == 0 && echoed.stdout == Data(text.utf8))
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let interpreter = directory.appending(path: "fake-voice-interpreter")
        try FileManager.default.createSymbolicLink(at: interpreter, withDestinationURL: URL(filePath: "/bin/sh"))
        let script = directory.appending(path: "stand-in")
        try Data("#!/usr/bin/env fake-voice-interpreter\nprintf '%s' \"$PATH\"\nprintf '%0600d' 0 >&2\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let environment = try await VoiceAskProcessRunner.run(script, arguments: [], input: Data())
        let paths = String(decoding: environment.stdout, as: UTF8.self).split(separator: ":").map(String.init)
        precondition(environment.status == 0 && paths.contains(directory.path) && paths.contains("/opt/homebrew/bin"),
                     "status \(environment.status), PATH \(paths), stderr \(String(decoding: environment.stderr, as: UTF8.self))")
        precondition(environment.stderr.count == 500)
        do {
            _ = try await VoiceAskProcessRunner.run(URL(filePath: "/usr/bin/true"), arguments: [],
                                                    input: Data(repeating: 65, count: 1_048_576))
            preconditionFailure("Expected broken pipe")
        } catch {
            precondition((error as NSError).code == NSFileWriteUnknownError || (error as NSError).code == 32)
        }
        print("PASS: env interpreter resolves via child PATH, stderr capped at 500 bytes, 1 MB broken pipe survives")
        for ignoresTermination in [false, true] {
            let pidFile = directory.appending(path: "pid")
            let command = "echo $$ > '\(pidFile.path)'; " + (ignoresTermination ? "trap '' TERM; exec sleep 30" : "exec sleep 30")
            let start = ContinuousClock.now
            try await expect(.timeout) {
                _ = try await VoiceAskProcessRunner.run(URL(filePath: "/bin/sh"), arguments: ["-c", command],
                                                        input: Data(), timeout: .milliseconds(100))
            }
            precondition(start.duration(to: .now) < .seconds(2.6))
            let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
            precondition(kill(pid, 0) == -1 && errno == ESRCH)
            print("PASS: timeout returns within timeout + grace; process dead, ignores TERM = \(ignoresTermination)")
        }
        let cancelPID = directory.appending(path: "cancel-pid")
        let cancelled = Task {
            try await VoiceAskProcessRunner.run(URL(filePath: "/bin/sh"),
                arguments: ["-c", "echo $$ > '\(cancelPID.path)'; trap '' TERM; exec sleep 30"], input: Data())
        }
        try await wait { FileManager.default.fileExists(atPath: cancelPID.path) }
        let cancellationStart = ContinuousClock.now
        cancelled.cancel()
        do { _ = try await cancelled.value; preconditionFailure("Expected cancellation") } catch is CancellationError {}
        let cancelledPID = Int32(try String(contentsOf: cancelPID, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines))!
        precondition(cancellationStart.duration(to: .now) < .seconds(2.6))
        precondition(kill(cancelledPID, 0) == -1 && errno == ESRCH)
        print("PASS: cancellation kills TERM-ignoring child and returns within grace")
        let pipeStart = ContinuousClock.now
        try await expect(.timeout) {
            _ = try await VoiceAskProcessRunner.run(URL(filePath: "/bin/sh"),
                arguments: ["-c", "sleep 3 & exit 0"], input: Data(), timeout: .milliseconds(100))
        }
        precondition(pipeStart.duration(to: .now) < .seconds(2.6))
        print("PASS: inherited grandchild pipes cannot hold run past timeout + grace")
        print("PASS: real platform process exit callback, stdin round trip and timeout using harmless stand-in executables")
    }

    @MainActor static func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        preconditionFailure("Message delivery timed out")
    }
}
