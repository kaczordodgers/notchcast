// notchcast-sources: Tinycast/Features/QuitProtection/Model/*.swift
// notchcast-sources: Tinycast/Features/QuitProtection/QuitProtectionModule.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import AppKit
import Observation

@MainActor protocol NotchcastModule { func start(); func stop() }
enum Paster { static let tinycastEventTag: Int64 = 12345 }
enum ASCIIKeyboardLayout {
    @MainActor static func character(for code: Int, modifiers: UInt32) -> String? { nil }
}
@MainActor final class EventTapHub {
    enum Verdict { case pass, swallow }
    func registerSynchronous(mask: CGEventMask,
                             handler: @escaping @Sendable (CGEventType, CGEvent) -> Verdict) -> UUID { UUID() }
    func remove(_ id: UUID) {}
    func refreshPermission() {}
}
@MainActor @Observable final class QuitProtectionStore {
    @ObservationIgnored var reads = 0
    private var stored = QuitProtectionEngine.Configuration()
    var configuration: QuitProtectionEngine.Configuration {
        get { reads += 1; return stored }
        set { stored = newValue }
    }
}

@main @MainActor struct QuitProtectionObservationTests {
    static func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }

    static func main() {
        let store = QuitProtectionStore()
        let module = QuitProtectionModule(store: store, hub: EventTapHub()) { nil }
        func readsAfterChange() -> Int {
            settle()
            var next = store.configuration
            next.closeEnabled.toggle()
            store.reads = 0
            store.configuration = next
            settle()
            return store.reads
        }
        module.start()
        let single = readsAfterChange()
        precondition(single > 0, "A configuration change must reach the module")
        module.stop()
        module.start()
        module.stop()
        module.start()
        let restarted = readsAfterChange()
        precondition(restarted == single, "Stop must end its chain: \(single) reads expected, got \(restarted)")
        module.stop()
        let stopped = readsAfterChange()
        precondition(stopped == 0, "A stopped module must not re-run, got \(stopped)")
        print("PASS: one configuration observation chain across stop/start")
    }
}

@MainActor final class AppCore {
    static let shared = AppCore()
    let appIndex = CommandIndexFixture()
}
@MainActor final class CommandIndexFixture {
    func refreshNotchcastCommands() {}
}
