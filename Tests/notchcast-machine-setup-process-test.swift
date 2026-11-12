// notchcast-sources: Tinycast/Features/MachineSetupProfile/Model/*.swift Tinycast/Features/MachineSetupProfile/Service/*.swift
// notchcast-sources: Tinycast/Features/MachineSetupProfile/MachineSetupProfileCoordinator+Command.swift
// notchcast-kit: command host
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
// notchcast-sources: Tinycast/Platform/ExecutableLocator.swift
import Foundation

@main
struct MachineSetupProcessTests {
    @MainActor
    static func main() async throws {
        NotchcastHost.current.confirm = { _, _, _, _ in
            fatalError("Confirmation is injected by the coordinator harness")
        }
        NotchcastHost.current.showMessage = { _, _ in
            fatalError("Presentation is injected by the coordinator harness")
        }
        NotchcastPreferences.shared.enabled = false
        let live = MachineSetupProfileProcessExecutor.live()
        let read = try live.process("/usr/bin/defaults", ["read", "com.apple.dock", "autohide"])
        precondition(read.status == 0 || read.status == 1)
        do { _ = try live.process("/bin/sh", ["-c", "true"]); fatalError("Expected rejection") } catch {}
        let policy = MachineSetupProfileEngine.Policy(appVersion: "1", fileKeys: [:],
            moduleKeys: [], tweakIDs: MachineSetupProfileProcessExecutor.tweakIDs)
        let profile = MachineSetupProfile(format: 1, appVersion: "1", backup: Data(),
            tweaks: ["dock.autohide", "system.firewall"], files: [:], modules: [:])
        let plan = try MachineSetupProfileEngine.plan(profile, policy: policy)
        var calls: [[String]] = []
        var enabled = false
        var executor = MachineSetupProfileProcessExecutor(process: { path, arguments in
            precondition(path == (arguments == ["Dock"] ? "/usr/bin/killall" : "/usr/bin/defaults"))
            calls.append(arguments)
            if arguments.first == "write" { enabled = true }
            return .init(status: enabled ? 0 : 1, output: enabled ? "1\n" : "missing key")
        }, isRoot: { false })
        try executor.preview(plan)
        precondition(calls.count == 1 && !enabled)
        precondition(executor.report.map(\.status) == [.planned, .needsHelper])
        try executor.apply(plan)
        precondition(enabled && calls == [
            ["read", "com.apple.dock", "autohide"],
            ["read", "com.apple.dock", "autohide"],
            ["write", "com.apple.dock", "autohide", "-bool", "true"],
            ["Dock"],
            ["read", "com.apple.dock", "autohide"]
        ])
        precondition(executor.report.map(\.status) == [.applied, .needsHelper])
        try executor.apply(plan)
        precondition(calls.count == 6 && executor.report.first?.status == .satisfied)
        var restartCalls: [[String]] = []
        var restartFailed = MachineSetupProfileProcessExecutor(process: { _, arguments in
            restartCalls.append(arguments)
            return .init(status: arguments == ["Dock"] ? 1 : 0, output: "0")
        }, isRoot: { false })
        do { try restartFailed.apply(plan); fatalError("Expected restart failure") } catch {}
        precondition(restartCalls == [
            ["read", "com.apple.dock", "autohide"],
            ["write", "com.apple.dock", "autohide", "-bool", "true"], ["Dock"]
        ])
        precondition(restartFailed.report.map(\.status) == [.failed, .notRun])
        var failed = MachineSetupProfileProcessExecutor(process: { _, _ in
            .init(status: 2, output: "private output")
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
        precondition(calls.count == 6)
        _ = try MachineSetupProfileRunner.run(profile, policy: policy, enabled: true, executor: &gated)
        precondition(calls.count == 6)
        for invalid in [
            MachineSetupProfile(format: 1, appVersion: "1", backup: Data([1]),
                tweaks: [], files: [:], modules: [:]),
            MachineSetupProfile(format: 1, appVersion: "1", backup: Data(),
                tweaks: [], files: ["config.json": ["theme": "dark"]], modules: [:]),
            MachineSetupProfile(format: 1, appVersion: "1", backup: Data(),
                tweaks: [], files: [:], modules: ["hoverDelay": "0.3"]),
            MachineSetupProfile(format: 1, appVersion: "1", backup: Data(),
                tweaks: ["unknown"], files: [:], modules: [:])
        ] {
            do {
                try gated.apply(.init(profile: invalid))
                fatalError("Unsupported payload must be rejected")
            } catch {}
        }
        precondition(calls.count == 6)
        var applied = 0
        var confirmed = 0
        var presented = 0
        var available = true
        let preview = MachineSetupProfileCoordinator.Outcome(
            steps: [.init(id: "dock.autohide", status: .planned)], succeeded: true)
        await MachineSetupProfileCoordinator.run(enabled: { available }, preview: { preview },
            confirm: { _ in confirmed += 1; return false },
            apply: { applied += 1; return preview }, present: { _ in presented += 1 })
        precondition(confirmed == 1 && applied == 0 && presented == 0)
        await MachineSetupProfileCoordinator.run(enabled: { available }, preview: { preview },
            confirm: { _ in available = false; return true },
            apply: { applied += 1; return preview }, present: { _ in presented += 1 })
        precondition(applied == 0)
        available = true
        await MachineSetupProfileCoordinator.run(enabled: { available }, preview: { preview },
            confirm: { _ in true }, apply: { applied += 1; return preview },
            present: { _ in presented += 1 })
        precondition(applied == 1 && presented == 1)
        await MachineSetupProfileCoordinator.run(enabled: { true },
            preview: { .init(steps: [], succeeded: false) },
            confirm: { _ in fatalError("Failed preview cannot confirm") },
            apply: { fatalError("Failed preview cannot apply") }, present: { _ in presented += 1 })
        precondition(presented == 2)
        print("machine setup process: PASS (real defaults read, shell rejection, preview, apply, idempotence, helper, failure, root, consent, unsupported)")
    }
}

enum NotchcastFeature { case machineSetupProfile }

@MainActor
enum BackupActions {
    static func chooseJSONFile() -> URL? { nil }
}

enum DialogTone { case success, danger }
