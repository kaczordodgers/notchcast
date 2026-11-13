// notchcast-sources: Tinycast/Features/SpacesOrder/Model/*.swift
// notchcast-sources: Tinycast/Features/SpacesOrder/Service/SpacesOrderModule.swift
import AppKit

@MainActor protocol NotchcastModule { func start(); func stop() }
@MainActor enum NotchcastIdentity {
    static let current = NotchcastIdentityValue()
    struct NotchcastIdentityValue { let defaults = UserDefaults.standard }
}
@MainActor struct NotchcastPreferences {
    static let shared = Self()
    enum Feature { case spacesOrder }
    func isOn(_ feature: Feature) -> Bool { true }
}

@main struct SpacesOrderLifecycleTests {
    @MainActor static func main() async {
        let domain = "app.notchcast.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var wake: CheckedContinuation<Void, Never>?
        var restarts = 0
        var succeeds = false
        let module = SpacesOrderModule(defaults: defaults, domain: domain,
            sleep: { await withCheckedContinuation { wake = $0 } },
            restart: { restarts += 1; return succeeds })
        module.start()
        precondition(restarts == 1)
        while wake == nil { await Task.yield() }
        module.stop()
        precondition(restarts == 2, "stop retries the pending Dock restart")
        succeeds = true
        wake?.resume(); wake = nil
        while restarts < 3 { await Task.yield() }
        precondition(defaults.string(forKey: SpacesOrderModule.backupKey) == nil)
        while wake == nil { await Task.yield() }
        wake?.resume(); wake = nil
        for _ in 0..<20 { await Task.yield() }
        precondition(wake == nil && restarts == 3, "stop ends polling after the pending restart succeeds")
        print("Spaces order: pending restart survives stop, retries, then ends polling")
    }
}
