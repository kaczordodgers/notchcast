// notchcast-sources: -strict-concurrency=complete -lsqlite3 Tinycast/Features/FleetPanel/Model/*.swift
// notchcast-sources: Tinycast/Features/FleetPanel/Service/*.swift Tinycast/Features/AgentThreads/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentThreads/Service/*.swift
// notchcast-sources: Tinycast/Features/AgentThreads/AgentThreadsModule.swift
// notchcast-kit: platform command
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-sources: Tinycast/Features/FleetPanel/FleetPanelModule+Registration.swift
// notchcast-sources: Tinycast/Features/AgentThreads/AgentThreadsModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-kit: host
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
import Foundation

enum TestFeature: Hashable { case fleetPanel, agentThreads, machLink }
typealias NotchcastFeature = TestFeature
enum DialogTone { case neutral }
@MainActor final class AppCore {}
@MainActor final class MachLinkManager {
    var routes: [String: @MainActor (MachLinkMessage) async throws -> MachLinkMessage] = [:]
    func register(_ method: String, _ route: @escaping @MainActor (MachLinkMessage) async throws -> MachLinkMessage) {
        routes[method] = route
    }
}
@MainActor final class MachLinkChannel {
    let manager = MachLinkManager()
    func request<T: Encodable, R: Decodable>(_ value: T, method: String, as: R.Type) async throws -> R {
        throw MachLinkMessage.Failure.disconnected
    }
}
@MainActor private final class FakeTransport: FleetTransport {
    var calls = 0
    var failure = false
    var otherFailure: MachLinkMessage.Failure?
    let snapshot: FleetSnapshot
    init(_ snapshot: FleetSnapshot) { self.snapshot = snapshot }
    func read() async throws -> FleetSnapshot {
        calls += 1
        if failure { throw MachLinkMessage.Failure.disconnected }
        if let otherFailure { throw otherFailure }
        let request = try MachLinkMessage.decode(MachLinkMessage(method: "agent-threads", value: true).encoded())
        let response = try await FleetMachLinkTransport.response(to: request, linkEnabled: true,
            featureEnabled: true, read: { self.snapshot })
        return try MachLinkMessage.decode(response.encoded()).value(as: FleetSnapshot.self)
    }
}
@MainActor private final class Gate {
    var continuations: [CheckedContinuation<FleetSnapshot, Never>] = []
    func read() async -> FleetSnapshot { await withCheckedContinuation { continuations.append($0) } }
}

private struct FakeProjects: AgentThreadProjectReading {
    func projects() async throws -> [AgentThreadProject] { [.init(id: "demo", title: "Demo")] }
}

@MainActor private final class ReadCounter {
    var calls = 0
    var cancellations = 0
}

private struct SlowRunner: AgentThreadRunning {
    let counter: ReadCounter
    func run(arguments: [String]) async throws -> Data {
        await MainActor.run { counter.calls += 1 }
        do { try await Task.sleep(for: .milliseconds(80)) } catch {
            await MainActor.run { counter.cancellations += 1 }
            throw error
        }
        return Data("""
        [{"threadId":"idle","status":"idle","link":"https://example.com/idle","updatedAt":"1970-01-01T02:46:40Z"},
        {"threadId":"done","status":"completed","link":"https://example.com/done","updatedAt":"1970-01-01T02:46:40Z"}]
        """.utf8)
    }
}

@main struct FleetPanelTest {
    @MainActor static func main() async throws {
        NotchcastPreferences.shared.only = []
        let now = Date(timeIntervalSince1970: 10_000)
        func row(_ id: String, _ phase: FleetSnapshot.Phase, age: Double = 0) -> FleetSnapshot.Row {
            .init(id: id, title: "Example", project: "Demo", model: "Example model", phase: phase,
                  pendingCount: 0, link: URL(string: "https://example.com/thread")!,
                  updatedAt: now.addingTimeInterval(-age))
        }
        let waiting = row("waiting", .waiting, age: 3000)
        let working = row("working", .working, age: 4000)
        let finished = row("finished", .finished, age: 1800)
        let snapshot = FleetSnapshot(rows: [finished, working, row("old", .finished, age: 1801), waiting], failure: nil)
        let column = snapshot.column(now: now, remote: false)
        let counter = ReadCounter()
        let state = AgentThreadsState(runner: SlowRunner(counter: counter), projects: FakeProjects(), now: { now })
        state.start()
        await state.waitUntilIdle()
        var userCompleted = false
        state.refresh { _ in userCompleted = true }
        let firstRead = Task { await FleetLocalSource.read(state: state, enabled: { true }) }
        let secondRead = Task { await FleetLocalSource.read(state: state, enabled: { true }) }
        let firstSnapshot = await firstRead.value
        let secondSnapshot = await secondRead.value
        precondition(firstSnapshot == secondSnapshot && firstSnapshot.rows.map(\.id) == ["done"])
        precondition(userCompleted && counter.calls == 2 && counter.cancellations == 0)
        let supersededRead = Task { await FleetLocalSource.read(state: state, enabled: { true }) }
        while counter.calls < 3 { await Task.yield() }
        userCompleted = false
        state.refresh { _ in userCompleted = true }
        let joinedSnapshot = await supersededRead.value
        precondition(joinedSnapshot.failure == nil && userCompleted && counter.calls == 4)
        state.stop()
        print("PASS: overlapping Fleet reads join user refresh; superseding user refresh completes; stale rows excluded")
        precondition(column == .rows([waiting, working, finished]))
        precondition(column.waiting == 1 && column.working == 1)
        precondition(waiting.updatedAgo(now: now) == 3000 && waiting.updatedAgo(now: .distantPast) == 0)
        precondition(FleetSnapshot(rows: [], failure: .off).column(now: now, remote: false) == .sourceOff)
        precondition(FleetSnapshot(rows: [], failure: .off).column(now: now, remote: true) == .remoteOff)
        precondition(FleetSnapshot(rows: [], failure: .failed).column(now: now, remote: true) == .failed)
        let transport = FakeTransport(snapshot)
        let module = FleetPanelModule(readLocal: { snapshot }, transport: transport, now: { now })
        module.start()
        await module.waitUntilIdle()
        precondition(module.local == column && module.remote == column)
        precondition(module.message.contains("1 waiting, 1 working"))
        transport.failure = true
        module.refresh()
        await module.waitUntilIdle()
        precondition(module.remote == .linkDown)
        transport.failure = false
        for error: MachLinkMessage.Failure in [.timedOut, .invalidMessage, .invalidPairing, .tooLarge] {
            transport.otherFailure = error
            module.refresh()
            await module.waitUntilIdle()
            precondition(module.remote == .failed)
        }
        transport.otherFailure = nil
        let request = try MachLinkMessage(method: "agent-threads", value: true)
        let timeoutGate = Gate()
        let started = ContinuousClock.now
        let timeoutResponse = try await FleetMachLinkTransport.response(to: request, linkEnabled: true,
            featureEnabled: true, timeout: .milliseconds(20), read: { await timeoutGate.read() })
        let timedOut = try timeoutResponse.value(as: FleetSnapshot.self)
        precondition(timedOut.failure == .failed && started.duration(to: .now) < .seconds(1))
        timeoutGate.continuations.first?.resume(returning: snapshot)
        print("PASS: responder deadline returns failed without waiting for or cancelling the shared refresh")
        var refreshes = 0
        NotchcastHost.current.refreshNotchcastCommands = { refreshes += 1 }
        let entries = FleetPanelModule.register(AppCore())
        precondition(entries.count == 1 && entries[0].requires == [.fleetPanel] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === FleetPanelModule.shared)
        let link = MachLinkChannel()
        FleetPanelModule.shared.transport = FleetMachLinkTransport(channel: link)
        guard let route = link.manager.routes["agent-threads"] else {
            preconditionFailure("Fleet transport did not register its route")
        }
        do {
            _ = try await route(request)
            preconditionFailure("Production route accepted a disabled link")
        } catch MachLinkMessage.Failure.disconnected {}
        NotchcastPreferences.shared.only = [.machLink]
        let routedOff = try await route(request)
        let routedSnapshot = try routedOff.value(as: FleetSnapshot.self)
        precondition(routedSnapshot.failure == .off)
        NotchcastPreferences.shared.only = []
        var reads = 0
        let off = try await FleetMachLinkTransport.response(to: request, linkEnabled: true,
            featureEnabled: false, read: { reads += 1; return snapshot })
        let offSnapshot = try off.value(as: FleetSnapshot.self)
        precondition(offSnapshot.failure == .off)
        precondition(reads == 0)
        do {
            _ = try await FleetMachLinkTransport.response(to: request, linkEnabled: false,
                featureEnabled: true, read: { snapshot })
            preconditionFailure("Disabled link accepted")
        } catch MachLinkMessage.Failure.disconnected {}
        let gate = Gate()
        transport.failure = false
        let late = FleetPanelModule(readLocal: { await gate.read() }, transport: transport, now: { now })
        let before = transport.calls
        late.start()
        while gate.continuations.count < 1 || transport.calls == before { await Task.yield() }
        late.refresh()
        while gate.continuations.count < 2 { await Task.yield() }
        gate.continuations[1].resume(returning: snapshot)
        await late.waitUntilIdle()
        gate.continuations[0].resume(returning: .init(rows: [], failure: .failed))
        for _ in 0..<20 { await Task.yield() }
        precondition(late.local == column)
        late.refresh()
        while gate.continuations.count < 3 { await Task.yield() }
        late.stop()
        gate.continuations[2].resume(returning: snapshot)
        for _ in 0..<20 { await Task.yield() }
        precondition(late.local == .sourceOff && late.remote == .linkDown)
        let unlinked = FleetPanelModule(readLocal: { snapshot }, now: { now })
        unlinked.start()
        await unlinked.waitUntilIdle()
        precondition(unlinked.local == column && unlinked.remote == .linkDown)
        unlinked.stop()
        let sourceOff = await FleetLocalSource.read()
        precondition(sourceOff.failure == .off)
        FleetPanelModule.shared.start()
        await FleetPanelModule.shared.waitUntilIdle()
        FleetPanelModule.shared.stop()
        precondition(refreshes == 2)
        NotchcastPreferences.shared.only = [.fleetPanel]
        precondition(FleetPanelModule.command.isEnabled())
        NotchcastPreferences.shared.only = []
        precondition(!FleetPanelModule.command.isEnabled())
        for state: FleetSnapshot.Column in [.sourceOff, .linkDown, .remoteOff, .failed] {
            precondition(!FleetPanelModule.localMessage(state).isEmpty)
            precondition(!FleetPanelModule.remoteMessage(state).isEmpty)
        }
        print("PASS: all column states; ordering and inclusive 30-minute window; injected elapsed time")
        print("PASS: parallel reads; stop and superseded results dropped; real Codable fake-transport round trip")
        print("PASS: route gates; command text and off gate; exact production hook init under strict Swift 6")
    }
}
