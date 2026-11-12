// notchcast-sources: Tinycast/Features/GreenMaximize/Model/*.swift
// notchcast-sources: Tinycast/Features/GreenMaximize/Service/*.swift
// notchcast-kit: core platform input isolated-identity
// notchcast-sources: Tests/Support/EventTapHubFake.swift
import AppKit

func AXIsProcessTrusted() -> Bool { false }
// The harness never maximizes: a full-screen answer ends any maximize before it moves a window.
enum AXWindowAccess {
    enum Anchor { case centered }
    static func isFullScreen(_ window: AXUIElement) -> Bool { true }
    static func frame(of window: AXUIElement) -> CGRect? { nil }
    static func application(for pid: pid_t, timeout: Float) -> AXUIElement { AXUIElementCreateApplication(pid) }
    static func suppressEnhancedUserInterface(on application: AXUIElement) -> () -> Void { {} }
    static func write(_ target: CGRect, anchor: Anchor, to window: AXUIElement, current: CGRect,
                      canResize: Bool, canvas: CGRect?) -> CGRect? { nil }
}
struct AXGeometry {
    init(screens: [NSScreen]) {}
    func flip(_ rect: CGRect) -> CGRect { rect }
}

@main @MainActor
struct GreenMaximizeModuleTests {
    static func main() {
        let hub = EventTapHub()
        let module = GreenMaximizeModule(hub: hub)
        module.start()
        module.start()
        precondition(hub.consumerCount == 1, "Start twice registers once")
        let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                            mouseCursorPosition: CGPoint(x: -10_000, y: -10_000), mouseButton: .left)!
        precondition(hub.handler!(.leftMouseDown, click) == .pass, "A click on no green button passes")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.2))
        precondition(hub.refreshes >= 1, "The 1 s timer still restarts a tap that failed to start")
        module.stop()
        module.stop()
        precondition(hub.consumerCount == 0 && hub.handler == nil)
        print("✓ GreenMaximize module: start once, click pass-through, timer restart and stop checks passed")
    }
}
