// notchcast-sources: Tinycast/Features/Tweaks/Model/AppleAppsPolicy.swift
// notchcast-sources: Tinycast/Features/Tweaks/Model/TypingPreferencePlan.swift
// notchcast-sources: Tinycast/Features/Tweaks/Service/AppleAppsUndoStore.swift
// notchcast-sources: Tinycast/Features/Tweaks/Service/AppleAppsService.swift
// notchcast-sources: Tinycast/Features/Tweaks/Service/AppleAppsUndoModule.swift
import Foundation

struct SystemToolsProcessRunner {
    func run(_ executable: String, arguments: [String]) throws -> String {
        preconditionFailure("Harness must inject a fake Dock restart")
    }
}

@MainActor protocol NotchcastModule {
    func start()
    func stop()
}

@main struct AppleAppsModuleTests {
    @MainActor static func main() throws {
        let suite = "test.apple-apps." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = try PropertyListSerialization.data(fromPropertyList: [
            ["tile-data": ["bundle-identifier": "com.apple.Music"]],
        ], format: .binary, options: 0)
        var dock = original
        var writes = 0
        var restarts = 0
        var refuseWrite = false
        var refuseRestart = false
        enum Failure: Error { case refused }
        func module() -> AppleAppsUndoModule {
            AppleAppsUndoModule(defaults: defaults, readDock: { dock }, writeDock: {
                precondition(defaults.data(forKey: "appleAppsUndoReceipt") != nil)
                if refuseWrite { throw Failure.refused }
                writes += 1
                dock = $0
            }, restartDock: {
                precondition(writes == restarts + 1)
                restarts += 1
                if refuseRestart { throw Failure.refused }
            })
        }
        let first = module()
        first.setDock(true)
        precondition(writes == 0)
        first.start()
        first.setDock(true)
        precondition(writes == 1 && restarts == 1 && first.store?.receipt.dock == original)
        let relaunched = module()
        precondition(relaunched.store?.receipt.dock == original)
        relaunched.stop()
        precondition(dock == original && writes == 2 && restarts == 2)
        precondition(module().store?.receipt.dock == nil)
        let failing = module()
        var failures = 0
        failing.onFailure = { _ in failures += 1 }
        failing.start()
        refuseWrite = true
        failing.setDock(true)
        precondition(failures == 1 && writes == 2 && restarts == 2)
        refuseWrite = false
        refuseRestart = true
        failing.setDock(false)
        precondition(failures == 2 && failing.store?.receipt.dock == original)
        refuseRestart = false
        failing.setDock(false)
        precondition(failing.store?.receipt.dock == nil && dock == original)
        defaults.set(Data([255]), forKey: "appleAppsUndoReceipt")
        let corrupt = module()
        var reported = false
        corrupt.onFailure = { _ in reported = true }
        corrupt.start()
        corrupt.setDock(true)
        precondition(reported && corrupt.store == nil && writes == 4 && restarts == 4)
        print("9 PASSED, 0 failed")
    }
}
