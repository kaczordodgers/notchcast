// notchcast-sources: -strict-concurrency=complete Tinycast/Features/AgentThreads/Model/AgentThread.swift
// notchcast-sources: Tinycast/Features/WaitingAlerts/Model/*.swift Tinycast/Features/WaitingAlerts/Service/*.swift
import Foundation

@MainActor protocol NotchcastModule { func start(); func stop() }
enum TestFeature { case waitingAlerts, agentThreads }
enum TestTone { case neutral }
struct NotchcastCommand {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: TestFeature
    let isEnabled: @MainActor () -> Bool
    let run: @MainActor () -> Void
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled = false
    func isOn(_ feature: TestFeature) -> Bool { enabled }
}
@MainActor final class TestIndex { func refreshNotchcastCommands() {} }
@MainActor final class AppCore {
    static let shared = AppCore()
    let appIndex = TestIndex()
    func showMessage(_ message: String, tone: TestTone) {}
}
@MainActor final class TestState {
    enum Status { case ready }
    let status = Status.ready
    var threads: [AgentThread] = []
    func refresh() {}
    func waitUntilIdle() async {}
}
@MainActor final class TestThreads { let state = TestState() }
@MainActor enum NotchcastCore {
    static let agentThreads = TestThreads()
    static let waitingAlerts = WaitingAlertsModule(availabilityChanged: { AppCore.shared.appIndex.refreshNotchcastCommands() })
}
@MainActor final class FakeWatcher: WaitingAlertsWatching {
    var changed: (@MainActor () -> Void)?
    var exists = true
    var stops = 0
    func start(path: String, changed: @escaping @MainActor () -> Void) -> Bool {
        self.changed = changed
        return exists
    }
    func stop() { stops += 1; changed = nil }
}
@MainActor final class Fixture {
    var time: TimeInterval = 0
    var calls = 0
    var rows: [AgentThread] = []
    var messages: [String] = []
    var readGate: CheckedContinuation<Void, Never>?
    var sleepGate: CheckedContinuation<Void, Never>?
    var block = false
    func read() async -> [AgentThread] {
        calls += 1
        if block { await withCheckedContinuation { readGate = $0 } }
        return rows
    }
    func sleep(_ delay: TimeInterval) async {
        precondition(delay > 0)
        await withCheckedContinuation { sleepGate = $0 }
    }
}
@main struct WaitingAlertsTest {
    static func thread(_ id: String, _ phase: AgentThread.Phase) -> AgentThread {
        AgentThread(id: id, title: "Example", project: "Demo", model: "", phase: phase,
                    pendingCount: 0, link: URL(string: "https://example.com")!,
                    updatedAt: Date(timeIntervalSince1970: 0), settled: false)
    }
    @MainActor static func settle() async { for _ in 0..<30 { await Task.yield() } }
    @MainActor static func main() async {
        let approval = WaitingAlertsEngine.waiting(in: [thread("one", .waitingForApproval)])
        let question = WaitingAlertsEngine.waiting(in: [thread("two", .waitingForInput)])
        precondition(WaitingAlertsEngine.notices(previous: nil, current: approval).isEmpty)
        precondition(WaitingAlertsEngine.notices(previous: [], current: approval) == approval)
        precondition(WaitingAlertsEngine.notices(previous: approval, current: approval).isEmpty)
        precondition(WaitingAlertsEngine.notices(previous: approval, current: []).isEmpty)
        precondition(WaitingAlertsEngine.notices(previous: [], current: approval) == approval)
        precondition(WaitingAlertsEngine.message(approval) == "Example is waiting for approval.")
        precondition(WaitingAlertsEngine.message(question) == "Example has a question.")
        precondition(WaitingAlertsEngine.message(approval + question) == "2 agents are waiting.")
        precondition(WaitingAlertsEngine.countMessage(0) == "No agents are waiting.")
        let fixture = Fixture()
        let watcher = FakeWatcher()
        fixture.rows = [thread("one", .waitingForApproval)]
        let module = WaitingAlertsModule(watcher: watcher, path: "/synthetic", read: { await fixture.read() },
            post: { fixture.messages.append($0) }, now: { fixture.time }, sleep: { await fixture.sleep($0) })
        module.start()
        await settle()
        precondition(fixture.calls == 1 && module.waitingCount == 1 && fixture.messages.isEmpty)
        watcher.changed?()
        watcher.changed?()
        await settle()
        precondition(fixture.calls == 1 && fixture.sleepGate != nil)
        fixture.time = 10
        fixture.block = true
        fixture.sleepGate?.resume(); fixture.sleepGate = nil
        await settle()
        precondition(fixture.calls == 2 && fixture.readGate != nil)
        watcher.changed?()
        watcher.changed?()
        await settle()
        precondition(fixture.calls == 2)
        fixture.rows += [thread("two", .waitingForInput)]
        fixture.readGate?.resume(); fixture.readGate = nil
        await settle()
        precondition(module.waitingCount == 2 && fixture.messages == ["Example has a question."])
        precondition(fixture.sleepGate != nil)
        fixture.time = 20
        fixture.sleepGate?.resume(); fixture.sleepGate = nil
        await settle()
        precondition(fixture.calls == 3)
        let late = watcher.changed
        module.stop()
        fixture.readGate?.resume(); fixture.readGate = nil
        late?()
        await settle()
        precondition(module.waitingCount == 0 && fixture.calls == 3 && watcher.stops == 1)
        watcher.exists = false
        module.start()
        module.refresh(report: true)
        precondition(fixture.messages.last == "T3 data folder is unavailable.")
        module.stop()
        precondition(!WaitingAlertsModule.command.isEnabled())
        NotchcastPreferences.shared.enabled = true
        precondition(WaitingAlertsModule.command.isEnabled())
        _ = NotchcastCore.waitingAlerts
        print("PASS: transitions, first-read suppression, coalescing, approval/question/count text")
        print("PASS: fake watcher, injected clock, 10-second throttle, one in flight, one trailing refresh")
        print("PASS: stop drops late result/event; missing folder; switch command gate; exact hook init; Swift 6 strict")
    }
}
