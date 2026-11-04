// notchcast-sources: Tinycast/Features/VoiceAsk/Model/*.swift
// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskModule.swift
// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskCLI*.swift
// notchcast-sources: Tinycast/Features/VoiceAsk/Service/VoiceAskProcessRunner.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift

import Foundation

@main
struct VoiceAskTransportTest {
    @MainActor final class Fixture {
        var launches = 0
        var status: Int32 = 0
        var text = VoiceAskTransportTest.completed
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

    @MainActor static func expect(_ error: VoiceAskCLIError, _ operation: () async throws -> Void) async throws {
        do { try await operation(); preconditionFailure("Expected an error") } catch let actual as VoiceAskCLIError {
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
            return .init(status: fixture.status, stdout: Data(fixture.text.utf8))
        })
        let text = "private spoken text\nsecond line"
        let reply = try await transport.send(text, destination: "fixture")
        precondition(reply == .init(state: .completed, firstLines: ["Done. The build is green and the PR is open."]))
        fixture.status = 1
        fixture.text = failed
        let failure = try await transport.send(text, destination: "fixture")
        precondition(failure == .init(state: .failed, firstLines: ["Provider returned an error: rate limited."]))
        fixture.status = 2
        fixture.text = waiting
        let pending = try await transport.send(text, destination: "fixture")
        precondition(pending.state == .running && pending.firstLines == ["The agent is waiting for an answer in T3 Code."])
        fixture.status = 0
        let pendingAtZero = try await transport.send(text, destination: "fixture")
        precondition(pendingAtZero == pending)
        fixture.text = "not JSON"
        try await expect(.invalidOutput) { _ = try await transport.send(text, destination: "fixture") }
        for destination in ["", "has space", "line\nbreak"] {
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
        let module = VoiceAskModule(defaults: defaults, begin: {}, finish: { text }, cancel: {})
        module.destination = "fixture"
        module.configure(transport: transport)
        let before = fixture.launches
        module.press(alone: true)
        try await Task.sleep(for: .milliseconds(300))
        module.release()
        precondition(fixture.launches == before)
        print("PASS: exact argv and stdin, three CLI fixtures, waiting status, off means no launch")
        print("PASS: invalid destination, missing CLI, bad JSON, timeout")
        let echoed = try await VoiceAskProcessRunner.run(URL(filePath: "/bin/cat"), arguments: [], input: Data(text.utf8))
        precondition(echoed.status == 0 && echoed.stdout == Data(text.utf8))
        try await expect(.timeout) {
            _ = try await VoiceAskProcessRunner.run(URL(filePath: "/bin/sleep"), arguments: ["5"],
                                                    input: Data(), timeout: .milliseconds(30))
        }
        print("PASS: real platform process exit callback, stdin round trip and timeout using harmless stand-in executables")
    }
}
