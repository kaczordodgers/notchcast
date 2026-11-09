// notchcast-sources: Tinycast/Features/QuitProtection/Model/*.swift Tinycast/Features/QuitProtection/Service/*.swift
// notchcast-sources: Tinycast/Features/QuitProtection/QuitProtectionModule.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Input/EventTapPolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Input/EventTapSubscription.swift
import AppKit

@MainActor protocol NotchcastModule { func start(); func stop() }
enum Paster { static let tinycastEventTag: Int64 = 12345 }
enum ASCIIKeyboardLayout {
    @MainActor static func character(for code: Int, modifiers: UInt32) -> String? {
        code == 12 ? "q" : code == 13 ? "w" : nil
    }
}
@MainActor final class EventTapHub {
    struct Event {}
    enum Verdict { case pass, swallow }
    func register(mask: CGEventMask, handler: @escaping @MainActor @Sendable (Event) -> Void) -> UUID { UUID() }
    var handler: (@Sendable (CGEventType, CGEvent) -> Verdict)?
    var count = 0
    func registerSynchronous(mask: CGEventMask,
                             handler: @escaping @Sendable (CGEventType, CGEvent) -> Verdict) -> UUID {
        precondition(mask != 0)
        self.handler = handler
        count += 1
        return UUID()
    }
    func remove(_ id: UUID) { count -= 1; handler = nil }
}
@main @MainActor struct ModuleTests {
    static func main() {
        let suite = "nc.quit.module.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let hub = EventTapHub()
        let store = QuitProtectionStore(defaults: defaults)
        store.configuration.mode = .doublePress
        var targetReads = 0
        let module = QuitProtectionModule(store: store, hub: hub) {
            targetReads += 1
            return .init(processIdentifier: 42, bundleIdentifier: "test.app", name: "Test")
        }
        module.start()
        module.start()
        precondition(hub.count == 1)
        let idleReads = targetReads
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        precondition(targetReads == idleReads, "Idle protection must not poll the target")
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)!
        event.flags = .maskCommand
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        event.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
        precondition(hub.handler?(.keyDown, event) == .pass)
        do {
            let physical = CGEvent(keyboardEventSource: nil, virtualKey: 12, keyDown: true)!
            physical.flags = .maskCommand
            physical.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            precondition(hub.handler?(.keyDown, physical) == .swallow,
                         "code \(event.getIntegerValueField(.keyboardEventKeycode)) flags \(event.flags.rawValue)")
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        precondition(module.notice != nil)
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString))
        RunLoop.main.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.8))
        precondition(module.notice == nil, "Deadline must fire in tracking mode")
        module.stop()
        module.stop()
        precondition(hub.count == 0 && module.notice == nil)
        print("PASS: module lifecycle, synchronous interception, synthetic bypass; no system effects")
    }
}

@MainActor final class AppCore {
    static let shared = AppCore()
    let appIndex = CommandIndexFixture()
}
@MainActor final class CommandIndexFixture {
    private(set) var refreshes = 0
    func refreshNotchcastCommands() { refreshes += 1 }
}
