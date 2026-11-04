// notchcast-sources: Tinycast/Features/AppUpdates/*/*.swift Tinycast/Features/AppUpdates/AppUpdatesModule*.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Foundation
@MainActor protocol NotchcastModule: AnyObject { func start(); func stop() }
@main struct ModuleTest {
    @MainActor static func main() async {
        var calls = 0
        var pending: CheckedContinuation<[AppUpdate], Never>?
        let module = AppUpdatesModule {
            calls += 1
            return await withCheckedContinuation { pending = $0 }
        }
        module.check()
        precondition(calls == 0)
        module.start()
        module.check()
        while pending == nil { await Task.yield() }
        precondition(module.checking && calls == 1)
        module.stop()
        pending?.resume(returning: [])
        for _ in 0..<20 { await Task.yield() }
        precondition(!module.checking && module.results.isEmpty)
        module.check()
        precondition(calls == 1)
        module.start()
        module.stop()
        print("PASS start, stop, switch off and stale result")
    }
}
