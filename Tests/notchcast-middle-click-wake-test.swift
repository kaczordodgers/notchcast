// notchcast-sources: Tinycast/Features/MiddleClick/Model/*.swift
// notchcast-sources: Tinycast/Features/MiddleClick/Service/MiddleClickModule.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import AppKit

@main
@MainActor
struct MiddleClickWakeTest {
    static func main() async throws {
        let hub = EventTapHub()
        let module = MiddleClickModule(hub: hub)
        module.start()
        expect(MiddleClickTouchSource.starts == 1 && hub.live == 1, "Enable registers the trackpads once")

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await wait { MiddleClickTouchSource.starts == 2 }
        expect(MiddleClickTouchSource.stops >= 1, "Wake stops the input read before sleep")
        expect(hub.registered == 2 && hub.live == 1, "Wake re-registers with one live hub handler")

        module.stop()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        expect(MiddleClickTouchSource.starts == 2 && hub.live == 0, "Wake after switch-off starts nothing")
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

enum Paster {
    static let tinycastEventTag: Int64 = 0x54494E59
}

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor
final class EventTapHub {
    enum Verdict: Sendable {
        case pass
        case swallow
    }

    typealias SynchronousHandler = @Sendable (CGEventType, CGEvent) -> Verdict

    private(set) var registered = 0
    private var handlers: Set<UUID> = []
    var live: Int { handlers.count }

    func registerSynchronous(mask: CGEventMask, handler: @escaping SynchronousHandler) -> UUID {
        registered += 1
        return handlers.insert(UUID()).memberAfterInsert
    }

    func remove(_ id: UUID) { handlers.remove(id) }

    func refreshPermission() {}
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
