// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityTransport.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityManager.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
import Foundation

@MainActor
private final class FakeTransport: AudioPriorityTransport {
    struct Failure: Error {}
    var inventory: [AudioPriorityDevice] = []
    var callback: (@Sendable () -> Void)?
    var writes = 0
    var fail = false
    func devices() -> [AudioPriorityDevice] { inventory }
    func defaultUID(for direction: AudioPriorityDevice.Direction) -> String? { "low" }
    func setDefault(uid: String, for direction: AudioPriorityDevice.Direction) throws {
        writes += 1
        if fail { throw Failure() }
    }
    func start(onChange: @escaping @Sendable () -> Void) { callback = onChange }
    func stop() { callback = nil }
}

@main
struct AudioPriorityWiringTests {
    @MainActor
    static func main() async {
        let suite = "audio-priority-test-" + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let store = AudioPriorityPreferences(suiteName: suite)
        store.save(.init(enabled: true, uids: ["high", "low"]), for: .output)
        let restored = AudioPriorityPreferences(suiteName: suite)
        precondition(restored.ranking(for: .output) == store.ranking(for: .output))
        let fake = FakeTransport()
        let manager = AudioPriorityManager(transport: fake, store: store) { _ in }
        manager.inventoryChanged = { store.update($0) }
        fake.inventory = [.init(uid: "low", name: "Low", direction: .output)]
        manager.start()
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
        precondition(fake.writes == 2)
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
        manager.stop()
        print("PASS: connect-only policy, persistence, forget; real store, fake transport")
    }

    @MainActor
    static func wait(until condition: () -> Bool) async {
        while !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}
