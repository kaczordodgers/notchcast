// notchcast-sources: Tinycast/Features/Tweaks/Model/AppleAppsPolicy.swift
// notchcast-sources: Tinycast/Features/Tweaks/Model/TypingPreferencePlan.swift
// notchcast-sources: Tinycast/Features/Tweaks/Service/AppleAppsUndoStore.swift
// notchcast-sources: Tinycast/Features/Tweaks/Service/AppleAppsService.swift
// notchcast-sources: Tinycast/Features/Tweaks/Service/AppleAppsUndoModule.swift
import Foundation

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
        func module() -> AppleAppsUndoModule {
            AppleAppsUndoModule(defaults: defaults, readDock: { dock }, writeDock: {
                precondition(defaults.data(forKey: "appleAppsUndoReceipt") != nil)
                writes += 1
                dock = $0
            })
        }
        let first = module()
        first.setDock(true)
        precondition(writes == 0)
        first.start()
        first.setDock(true)
        precondition(writes == 1 && first.store?.receipt.dock == original)
        let relaunched = module()
        precondition(relaunched.store?.receipt.dock == original)
        relaunched.stop()
        precondition(dock == original && writes == 2)
        precondition(module().store?.receipt.dock == nil)
        defaults.set(Data([255]), forKey: "appleAppsUndoReceipt")
        let corrupt = module()
        var reported = false
        corrupt.onFailure = { _ in reported = true }
        corrupt.start()
        corrupt.setDock(true)
        precondition(reported && corrupt.store == nil && writes == 2)
        print("6 PASSED, 0 failed")
    }
}
