// notchcast-sources: Tinycast/Features/AgentFleet/Fleet/FleetSnapshot.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Fleet/FleetThreadSource.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Fleet/FleetModel.swift
// notchcast-sources: Tinycast/Features/AgentFleet/Fleet/FleetModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation

@MainActor
enum NotchcastCore {}

@MainActor
final class FakeFleetSource: FleetThreadSource {
    var calls = 0
    var snapshots: [String: FleetSnapshot] = [:]
    var failures: [String: FleetSnapshot.Failure] = [:]
    var suspended = false
    var pending: [CheckedContinuation<FleetSnapshot, any Error>] = []

    func read(_ destination: FleetSnapshot.Destination) async throws -> FleetSnapshot {
        calls += 1
        if suspended { return try await withCheckedThrowingContinuation { pending.append($0) } }
        if let failure = failures[destination.machine] { throw failure }
        return snapshots[destination.machine]!
    }
}

@main
@MainActor
struct FleetTests {
    static let now = Date(timeIntervalSince1970: 10_000)
    static func thread(
        _ id: String, _ state: FleetSnapshot.State, ended: TimeInterval? = nil,
        parent: String? = nil, path: String? = nil
    ) -> FleetSnapshot.Thread {
        .init(id: id, title: id, project: "Sample", engine: "Engine", state: state,
              began: now.addingTimeInterval(-3_600), ended: ended.map { now.addingTimeInterval($0) },
              parentID: parent, workspacePath: path)
    }

    static func main() async throws {
        let suite = "fleet-test-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        precondition(!NotchcastPreferences(suiteName: suite).isOn(.fleetPanel))
        precondition(!NotchcastFeature.fleetPanel.needsIsland)
        let source = FakeFleetSource()
        let local = FleetSnapshot.Destination(machine: "local", environmentID: "sample-local",
                                              workspacePath: nil, route: .local)
        let remote = FleetSnapshot.Destination(machine: "remote", environmentID: "sample-remote",
                                               workspacePath: nil, route: .linked)
        let report = try JSONDecoder().decode(FleetSnapshot.GuardReport.self, from: Data("""
        {"machine":"local","running":1,"max":3,"heavy":{"running":1,"max":3},
         "light":{"running":0,"max":0},"ventures":{"sample":1},
         "leads":[{"id":"lead","children":2,"venture":"sample","weight":"heavy"}]}
        """.utf8))
        let limits = try JSONDecoder().decode(FleetSnapshot.Limits.self, from: Data("""
        {"leads":{"heavy":3,"light":0},"childCap":2,"ventureChildCaps":{"sample":5},
         "ventureCaps":{"sample":2}}
        """.utf8))
        let snapshot = FleetSnapshot(threads: [
            thread("lead", .working), thread("child", .waiting, parent: "lead"),
            thread("boundary", .finished, ended: -1_800), thread("old", .finished, ended: -1_800.001),
            thread("excluded", .working, path: "/sample/agent-2784f2ac/work")
        ] + (0..<15).map { thread("worker-\($0)", .working) }, report: report, limits: limits)
        source.snapshots = ["local": snapshot, "remote": .init(threads: [], report: nil, limits: nil)]
        let model = FleetModel(source: source, destinations: [local, remote], clock: { now })
        for _ in 0..<20 { await Task.yield() }
        precondition(source.calls == 0)
        await model.refresh()
        precondition(model.rows.count == 18)
        precondition(model.rows.first?.thread.id == "child")
        precondition(model.rows.last?.thread.id == "boundary")
        precondition(model.rows.first?.thread.parentID == "lead")
        let lead = model.rows.first { $0.thread.id == "lead" }!
        precondition(lead.childCount == 2 && lead.childCap == 5 && lead.weight == "heavy")
        precondition(model.machines[0].report?.heavy.running == 1)
        precondition(model.machines[0].limits?.ventureCaps?["sample"] == 2)
        let count = source.calls
        for _ in 0..<20 { await Task.yield() }
        precondition(source.calls == count)
        source.failures["remote"] = .linkExpired
        await model.refresh()
        precondition(model.machines[1].message == "MBP link expired: relink in T3")
        precondition(model.rows.count == 18)
        source.failures = ["local": .unavailable]
        source.snapshots["remote"] = .init(threads: [thread("remote-worker", .working)], report: nil, limits: nil)
        await model.refresh()
        precondition(model.rows.count == 1 && model.rows[0].id.machine == "remote")
        source.suspended = true
        model.destinations = [local]
        let old = Task { await model.refresh() }
        while source.pending.isEmpty { await Task.yield() }
        let recent = Task { await model.refresh() }
        while source.pending.count < 2 { await Task.yield() }
        source.pending[1].resume(returning: .init(threads: [thread("new", .waiting)], report: nil, limits: nil))
        await recent.value
        source.pending[0].resume(returning: snapshot)
        await old.value
        precondition(model.rows.map(\.thread.id) == ["new"])
        let changed = Task { await model.refresh() }
        while source.pending.count < 3 { await Task.yield() }
        model.destinations = [remote]
        source.pending[2].resume(returning: snapshot)
        await changed.value
        precondition(model.rows.isEmpty && !model.isRefreshing)
        source.suspended = false
        let module = FleetModule()
        module.configure(source: source, destinations: [remote], clock: { now })
        let beforeStart = source.calls
        module.start()
        precondition(source.calls == beforeStart)
        await module.refresh()
        precondition(module.model?.rows.count == 1)
        module.stop()
        precondition(module.model?.rows.isEmpty == true)
        print("Fleet panel tests passed")
    }
}
