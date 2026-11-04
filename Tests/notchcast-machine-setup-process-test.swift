// notchcast-sources: Tinycast/Features/MachineSetupProfile/Model/*.swift Tinycast/Features/MachineSetupProfile/Service/*.swift
import Foundation

@main
struct MachineSetupProcessTests {
    static func main() throws {
        let policy = MachineSetupProfileEngine.Policy(appVersion: "1", fileKeys: [:],
            moduleKeys: [], tweakIDs: MachineSetupProfileProcessExecutor.tweakIDs)
        let profile = MachineSetupProfile(format: 1, appVersion: "1", backup: Data(),
            tweaks: ["dock.autohide", "system.firewall"], files: [:], modules: [:])
        let plan = try MachineSetupProfileEngine.plan(profile, policy: policy)
        var calls: [[String]] = []
        var enabled = false
        var executor = MachineSetupProfileProcessExecutor(process: { path, arguments in
            precondition(path == "/usr/bin/defaults")
            calls.append(arguments)
            if arguments.first == "write" { enabled = true }
            return .init(status: 0, output: enabled ? "1\n" : "0\n")
        }, isRoot: { false })
        try executor.preview(plan)
        precondition(calls.count == 1 && !enabled)
        precondition(executor.report.map(\.status) == [.planned, .needsHelper])
        try executor.apply(plan)
        precondition(enabled && calls.count == 4)
        precondition(executor.report.map(\.status) == [.applied, .needsHelper])
        try executor.apply(plan)
        precondition(calls.count == 5 && executor.report.first?.status == .satisfied)
        var failed = MachineSetupProfileProcessExecutor(process: { _, _ in
            .init(status: 1, output: "private output")
        }, isRoot: { false })
        do { try failed.apply(plan); fatalError("Expected failure") } catch {}
        precondition(failed.report.map(\.status) == [.failed, .notRun])
        var root = MachineSetupProfileProcessExecutor(process: { _, _ in
            fatalError("Root must never launch")
        }, isRoot: { true })
        do { try root.apply(plan); fatalError("Expected rejection") } catch {}
        var gated = executor
        do {
            _ = try MachineSetupProfileRunner.run(profile, policy: policy, enabled: true,
                dryRun: false, confirmed: false, executor: &gated)
            fatalError("Expected consent rejection")
        } catch {}
        precondition(calls.count == 5)
        print("machine setup process: PASS (preview, apply, idempotence, helper, failure, root, consent)")
    }
}
