// notchcast-sources: Tinycast/Features/MachineSetupProfile/Model/*.swift
// notchcast-sources: Tinycast/Features/MachineSetupProfile/Service/MachineSetupProfileProcessExecutor.swift
// notchcast-sources: Tinycast/Features/MachineSetupProfile/Service/MachineSetupProfileRunner.swift
import Foundation

@main struct SetupRollbackTest {
    static func main() throws {
        let profile = MachineSetupProfile(format: 1, appVersion: "1", backup: Data(),
            tweaks: ["dock.autohide"], files: [:], modules: [:])
        for missing in [false, true] {
            for throwsOnRestart in [false, true] {
                var calls: [[String]] = []
                var executor = MachineSetupProfileProcessExecutor(process: { _, args in
                    calls.append(args)
                    if args.first == "read" { return .init(status: missing ? 1 : 0, output: "0") }
                    if args == ["Dock"], calls.count == 3 {
                        if throwsOnRestart { throw MachineSetupProfileProcessExecutor.Failure.stepFailed }
                        return .init(status: 1, output: "")
                    }
                    return .init(status: 0, output: "")
                }, isRoot: { false })
                do { try executor.apply(.init(profile: profile)); fatalError("Restart must fail") } catch {}
                let restore = missing ? ["delete", "com.apple.dock", "autohide"]
                    : ["write", "com.apple.dock", "autohide", "-bool", "false"]
                precondition(calls.suffix(2) == [restore, ["Dock"]], "Restore original preference and restart Dock")
                precondition(executor.report == [.init(id: "dock.autohide", status: .failed)])
            }
        }
        for throwsOnWrite in [false, true] {
            var calls: [[String]] = []
            var executor = MachineSetupProfileProcessExecutor(process: { _, args in
                calls.append(args)
                if args.first == "read" { return .init(status: 0, output: "0") }
                if throwsOnWrite { throw MachineSetupProfileProcessExecutor.Failure.stepFailed }
                return .init(status: 1, output: "")
            }, isRoot: { false })
            do { try executor.apply(.init(profile: profile)); fatalError("Write must fail") } catch {}
            precondition(calls.count == 2, "Failed write must not restore or restart Dock")
            precondition(executor.report == [.init(id: "dock.autohide", status: .failed)])
        }
        print("PASS Dock rollback and thrown/nonzero write failures without restore or restart")
    }
}
