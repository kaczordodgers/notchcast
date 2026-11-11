// notchcast-sources: Tinycast/Features/MiddleClick/Model/*.swift
// notchcast-sources: Tinycast/Features/MiddleClick/Service/MiddleClickModule.swift
// notchcast-kit: platform input
// notchcast-sources: Tests/Support/EventTapHubFake.swift
import AppKit

@main
@MainActor
struct MiddleClickWakeTest {
    static func main() async throws {
        let hub = EventTapHub()
        let module = MiddleClickModule(hub: hub)
        module.start()
        expect(MiddleClickTouchSource.starts == 1 && hub.consumerCount == 1, "Enable registers the trackpads once")

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await wait { MiddleClickTouchSource.starts == 2 }
        expect(MiddleClickTouchSource.stops >= 1, "Wake stops the input read before sleep")
        expect(hub.registered == 2 && hub.consumerCount == 1, "Wake re-registers with one live hub handler")

        module.stop()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        expect(MiddleClickTouchSource.starts == 2 && hub.consumerCount == 0, "Wake after switch-off starts nothing")
        print("ALL PASSED: middle click re-registers its trackpads on wake")
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Timed out waiting for the wake restart")
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func expect(_ value: Bool, _ message: String) {
        precondition(value, message)
        print("PASS  \(message)")
    }
}

func AXIsProcessTrusted() -> Bool { true }

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor
final class MiddleClickTouchSource {
    static var starts = 0
    static var stops = 0

    init?() {}

    func start(_ sink: @escaping @Sendable (Int, [TouchPoint], TimeInterval) -> Void) -> Bool {
        Self.starts += 1
        return true
    }

    func stop() { Self.stops += 1 }
}
