// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityTransport.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityManager.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation

@MainActor
private final class FakeTransport: AudioPriorityTransport {
    struct Failure: Error {}
    var inventory: [AudioPriorityDevice] = []
    var callback: (@Sendable () -> Void)?
    var writes = 0
    var stops = 0
    var fail = false
    func devices() -> [AudioPriorityDevice] { inventory }
    func defaultUID(for direction: AudioPriorityDevice.Direction) -> String? { "low" }
    func setDefault(uid: String, for direction: AudioPriorityDevice.Direction) throws {
        writes += 1
        if fail { throw Failure() }
    }
    func start(onChange: @escaping @Sendable () -> Void) { callback = onChange }
    func stop() { stops += 1; callback = nil }
}

@MainActor
private final class FakeModule: NotchcastModule {
    let manager: AudioPriorityManager
    init(_ manager: AudioPriorityManager) { self.manager = manager }
    func start() { manager.start() }
    func stop() { manager.stop() }
}

@main
struct AudioPriorityWiringTests {
    @MainActor
    static func main() async {
        let suite = "audio-priority-test-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let store = AudioPriorityPreferences(suiteName: suite)
        store.save(.init(enabled: true, uids: ["high", "low"]), for: .output)
        let restored = AudioPriorityPreferences(suiteName: suite)
        precondition(restored.ranking(for: .output) == store.ranking(for: .output))
        let fake = FakeTransport()
        var failures = 0
        let manager = AudioPriorityManager(transport: fake, store: store) { _ in
            failures += 1
            store.failure = "failure"
        }
        manager.inventoryChanged = { store.update($0) }
        manager.succeeded = { store.failure = nil }
        fake.inventory = [.init(uid: "low", name: "Low", direction: .output)]
        let controller = NotchcastModuleController([
            .init(requires: [.audioPriority], module: FakeModule(manager))
        ], preferences: preferences)
        controller.run()
        precondition(fake.callback == nil)
        preferences.set(.audioPriority, true)
        await wait { fake.callback != nil }
        precondition(fake.callback != nil && fake.writes == 0)
        fake.inventory.append(.init(uid: "high", name: "High", direction: .output))
        fake.callback?()
        await wait { fake.writes == 1 }
        precondition(fake.writes == 1)
        fake.inventory.removeAll { $0.uid == "high" }
        fake.callback?()
        await wait { !store.devices.contains(where: { $0.uid == "high" }) }
        precondition(fake.writes == 1)
        fake.inventory.append(.init(uid: "high", name: "High", direction: .output))
        fake.fail = true
        fake.callback?()
        await wait { fake.writes == 2 }
        fake.callback?()
        await wait { store.devices.contains(where: { $0.uid == "high" }) }
        precondition(fake.writes == 2 && failures == 1 && store.failure == "failure")
        fake.inventory.removeAll { $0.uid == "high" }
        fake.callback?()
        await wait { !store.devices.contains(where: { $0.uid == "high" }) }
        store.forget("high", direction: .output)
        precondition(!store.outputs.contains("high"))
        fake.fail = false
        store.save(.init(enabled: true, uids: ["high", "low"]), for: .output)
        fake.inventory.append(.init(uid: "high", name: "High", direction: .output))
        fake.callback?()
        await wait { fake.writes == 3 }
        precondition(store.failure == nil)
        let late = fake.callback
        preferences.set(.audioPriority, false)
        await wait { fake.callback == nil }
        late?()
        await Task.yield()
        precondition(fake.writes == 3 && fake.stops == 1 && fake.callback == nil)
        print("PASS: switch lifecycle, stale events, connect-only policy, persistence, failure once; fake only")
    }

    @MainActor
    static func wait(until condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for state")
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
