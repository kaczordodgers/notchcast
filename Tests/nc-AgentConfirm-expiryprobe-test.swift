// notchcast-sources: Tinycast/Features/AgentConfirm/Model/*.swift Tinycast/Features/AgentConfirm/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Model/AgentConsentPolicy.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Service/AgentGrantStore.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift Tinycast/Features/AgentBridge/Service/AgentActionIndex.swift
import Foundation

@MainActor
final class Screen {
    var open: CheckedContinuation<Int, Never>?

    func close(_ index: Int) {
        open?.resume(returning: index)
        open = nil
    }
}

// Temporary diagnostic: measures the runner's timers and the expiry harness's answer window. Always fails so CI prints it.
@main
@MainActor
struct ConfirmationExpiryProbe {
    static let clock = ContinuousClock()

    static func ms(_ duration: Duration) -> Int { Int(duration / .milliseconds(1)) }

    static func scenario(yielding: Bool = false, answerDelay: Duration?) async throws -> String {
        let suite = "test.confirmation.expiryprobe." + UUID().uuidString
        let grants = try AgentGrantStore(bundleIdentifier: suite)
        defer {
            UserDefaults(suiteName: suite + ".notchcast.agent-consent")?
                .removePersistentDomain(forName: suite + ".notchcast.agent-consent")
        }
        var shown: [String] = []
        let screen = Screen()
        let authorization = AgentConfirmationAuthorization(grants: grants, isEnabled: { true },
            timeout: .milliseconds(100)) { action, _, choices in
            shown.append(action.id)
            return await withTaskCancellationHandler {
                await withCheckedContinuation { screen.open = $0 }
            } onCancel: {
                Task { @MainActor in screen.close(choices.count - 1) }
            }
        }
        let index = AgentActionIndex()
        var runs: [String] = []
        for id in ["first", "second"] {
            try index.register(.init(action: .init(id: id, title: id), run: { _ in
                runs.append(id)
                return .null
            }))
        }
        index.authorize = { action, parameters in await authorization.authorize(action, parameters: parameters) }
        index.start()
        let begin = clock.now
        let first = await index.handle(AgentRequest(verb: .run, id: "first"))
        let firstMs = ms(clock.now - begin)
        for _ in 0..<100 where screen.open != nil { try await Task.sleep(for: .milliseconds(10)) }
        let start = clock.now
        let wallStart = Date()
        let second = Task { await index.handle(AgentRequest(verb: .run, id: "second")) }
        var polls = 0
        for _ in 0..<100 where screen.open == nil {
            polls += 1
            if yielding { await Task.yield() } else { try await Task.sleep(for: .milliseconds(10)) }
        }
        if let answerDelay { try await Task.sleep(for: answerDelay) }
        let window = ms(clock.now - start)
        let wall = Int(Date().timeIntervalSince(wallStart) * 1000)
        let open = screen.open != nil
        screen.close(0)
        let reply = await second.value
        authorization.stop()
        let passed = first.code == .declined && shown == ["first", "second"] && reply.code == .ok && runs == ["second"]
        return "\(passed ? "pass" : "FAIL") first=\(firstMs)ms window=\(window)ms wall=\(wall)ms polls=\(polls) "
            + "openAtAnswer=\(open) code=\(reply.code) shown=\(shown) runs=\(runs)"
    }

    static func main() async throws {
        var sleeps: [Int] = []
        for _ in 0..<60 {
            let begin = clock.now
            try await Task.sleep(for: .milliseconds(10))
            sleeps.append(ms(clock.now - begin))
        }
        print("PROBE sleep(10ms) actual ms sorted: \(sleeps.sorted())")
        var failures = 0
        for round in 0..<40 {
            let line = try await scenario(answerDelay: nil)
            if line.hasPrefix("FAIL") { failures += 1 }
            print("PROBE round \(round): \(line)")
        }
        print("PROBE natural failures: \(failures)/40")
        var yieldFailures = 0
        for round in 0..<200 {
            let line = try await scenario(yielding: true, answerDelay: nil)
            if line.hasPrefix("FAIL") { yieldFailures += 1 }
            if round < 5 || line.hasPrefix("FAIL") { print("PROBE yield round \(round): \(line)") }
        }
        print("PROBE yield-wait failures: \(yieldFailures)/200")
        print("PROBE forced late answer (150ms): \(try await scenario(answerDelay: .milliseconds(150)))")
        print("PROBE forced answer inside the window (50ms): \(try await scenario(answerDelay: .milliseconds(50)))")
        exit(1)
    }
}
