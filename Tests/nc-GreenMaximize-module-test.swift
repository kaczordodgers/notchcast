// notchcast-sources: Tinycast/Features/GreenMaximize/Model/*.swift
// notchcast-sources: Tinycast/Features/GreenMaximize/Service/*.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
// notchcast-sources: Tinycast/Features/Notchcast/Input/EventTapPolicy.swift
// notchcast-sources: Tinycast/Features/Notchcast/Input/EventTapSubscription.swift
import AppKit

@MainActor protocol NotchcastModule { func start(); func stop() }
enum Paster { static let tinycastEventTag: Int64 = 12345 }
func AXIsProcessTrusted() -> Bool { false }
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var greenMaximizeExcludedApps = ""
}

@MainActor final class EventTapHub {
    struct Event {}
    enum Verdict { case pass, swallow }
    var handler: (@Sendable (CGEventType, CGEvent) -> Verdict)?
    var count = 0
    var refreshes = 0
    func registerSynchronous(mask: CGEventMask,
                             handler: @escaping @Sendable (CGEventType, CGEvent) -> Verdict) -> UUID {
        self.handler = handler
        count += 1
        return UUID()
    }
    func register(mask: CGEventMask, handler: @escaping @MainActor @Sendable (Event) -> Void) -> UUID { UUID() }
    func remove(_ id: UUID) { count -= 1; handler = nil }
    func refreshPermission() { refreshes += 1 }
}

@main @MainActor
struct GreenMaximizeModuleTests {
    static func main() {
        let hub = EventTapHub()
        let module = GreenMaximizeModule(hub: hub)
        module.start()
        module.start()
        precondition(hub.count == 1, "Start twice registers once")
        let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                            mouseCursorPosition: CGPoint(x: -10_000, y: -10_000), mouseButton: .left)!
        precondition(hub.handler!(.leftMouseDown, click) == .pass, "A click on no green button passes")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.2))
        precondition(hub.refreshes >= 1, "The 1 s timer still restarts a tap that failed to start")
        module.stop()
        module.stop()
        precondition(hub.count == 0 && hub.handler == nil)
        print("✓ GreenMaximize module: start once, click pass-through, timer restart and stop checks passed")
    }
}
