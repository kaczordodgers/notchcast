// notchcast-sources: Tinycast/Features/AgentAnswer/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentAnswer/Service/AgentAnswerModule.swift
// notchcast-sources: Tinycast/Features/AgentAnswer/Service/AgentAnswerTransport.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift

import Foundation

@MainActor
final class PendingFixture: AgentAnswerPendingSource {
    var calls = 0
    var fails = false
    var suspended = false
    var continuation: CheckedContinuation<[AgentAnswerItem], Never>?
    let item = AgentAnswerItem(id: "fixture", revision: "1", source: .bot, question: "Continue?")

    func pendingItems() async throws -> [AgentAnswerItem] {
        calls += 1
        if suspended {
            return await withCheckedContinuation { continuation = $0 }
        }
        if fails { throw URLError(.notConnectedToInternet) }
        return [item]
    }
}

@main
struct PendingPollingTest {
    @MainActor static func main() async throws {
        let fixture = PendingFixture()
        let module = AgentAnswerModule(pollInterval: .milliseconds(20))
        module.configure(source: fixture)
        try await Task.sleep(for: .milliseconds(30))
        precondition(fixture.calls == 0)
        module.start()
        try await Task.sleep(for: .milliseconds(30))
        precondition(module.items == [fixture.item])
        module.stop()
        let stoppedCalls = fixture.calls
        try await Task.sleep(for: .milliseconds(60))
        precondition(fixture.calls == stoppedCalls && module.items.isEmpty)
        fixture.fails = true
        module.start()
        try await Task.sleep(for: .milliseconds(250))
        precondition(fixture.calls - stoppedCalls >= 2 && module.pollingFailure != nil)
        module.stop()
        let failedCalls = fixture.calls
        try await Task.sleep(for: .milliseconds(250))
        precondition(fixture.calls == failedCalls)
        fixture.fails = false
        fixture.suspended = true
        module.start()
        while fixture.continuation == nil { await Task.yield() }
        module.stop()
        fixture.continuation?.resume(returning: [fixture.item])
        try await Task.sleep(for: .milliseconds(30))
        precondition(module.items.isEmpty && module.pollingFailure == nil)
        print("PASS: switch-scoped polling, stop cancellation, exponential backoff, stale result discarded")
    }
}
