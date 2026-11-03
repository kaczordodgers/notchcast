import ApplicationServices
import Foundation
import Synchronization

// Only the recorded worker invokes these callback handles; CF permits cross-thread loop control.
private struct TapRecord: @unchecked Sendable {
    let port: CFMachPort
    let runLoop: CFRunLoop
    let callback: CGEventTapCallBack
    let context: UnsafeMutableRawPointer?
    let mask: CGEventMask
}

private struct Fixture {
    var trusted = false
    var records: [TapRecord] = []
    var enabledCount = 0
    var disabledCount = 0
    var synchronousCount = 0
    var swallowedCount = 0
    var failNext = false
    var wrongConfiguration = false
}

private let fixture = Mutex(Fixture())

func AXIsProcessTrusted() -> Bool { fixture.withLock { $0.trusted } }

extension CGEvent {
    static func tapCreate(
        tap: CGEventTapLocation, place: CGEventTapPlacement, options: CGEventTapOptions,
        eventsOfInterest: CGEventMask, callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        let fail = fixture.withLock { state in
            let fail = state.failNext
            state.failNext = false
            state.wrongConfiguration = state.wrongConfiguration || Thread.isMainThread
                || tap != .cgSessionEventTap || place != .headInsertEventTap || options != .defaultTap
            return fail
        }
        guard !fail else { return nil }
        var context = CFMachPortContext()
        guard let port = CFMachPortCreate(nil, { _, _, _, _ in }, &context, nil),
            let runLoop = CFRunLoopGetCurrent()
        else { return nil }
        fixture.withLock {
            $0.records.append(TapRecord(port: port, runLoop: runLoop, callback: callback, context: userInfo,
                                       mask: eventsOfInterest))
        }
        return port
    }

    static func tapEnable(tap: CFMachPort, enable: Bool) {
        fixture.withLock {
            if enable { $0.enabledCount += 1 } else { $0.disabledCount += 1 }
        }
    }
}

@main
@MainActor
struct NotchcastTapHubTests {
    static var checks = 0

    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        guard condition else { fatalError(message) }
    }

    static func eventually(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(1)) } catch { fatalError("Unexpected cancellation") }
        }
        expect(condition(), "Timed out waiting for worker")
    }

    private nonisolated static func send(_ types: [CGEventType], through record: TapRecord) {
        CFRunLoopPerformBlock(record.runLoop, CFRunLoopMode.defaultMode.rawValue) {
            for type in types {
                guard let event = CGEvent(source: nil) else { fatalError("Could not make an unposted event") }
                let proxy = OpaquePointer(Unmanaged.passUnretained(record.port).toOpaque())
                let result = record.callback(proxy, type, event, record.context)
                if result == nil { fixture.withLock { $0.swallowedCount += 1 } }
            }
        }
        CFRunLoopWakeUp(record.runLoop)
    }

    static func policyTests() {
        var policy = EventTapPolicy()
        let first = UUID()
        let second = UUID()
        let key = EventTapPolicy.mask(for: .keyDown)
        let mouse = EventTapPolicy.mask(for: .otherMouseDown)
        expect(!policy.needsTap && policy.mask == 0, "Empty policy has no tap")
        policy.register(first, mask: key)
        expect(policy.needsTap && policy.mask == key, "First consumer starts a tap")
        policy.register(second, mask: mouse | key)
        expect(policy.mask == key | mouse, "Masks merge with OR")
        policy.register(first, mask: mouse)
        expect(policy.consumers.count == 2, "Replacing a registration preserves its identity")
        policy.remove(second)
        expect(policy.needsTap && policy.mask == mouse, "Removal shrinks the merged mask")
        policy.remove(UUID())
        expect(policy.mask == mouse, "Unknown removal is harmless")
        policy.remove(first)
        expect(!policy.needsTap && policy.mask == 0, "Last removal stops the tap")
        for type in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            expect(EventTapPolicy.shouldReenable(type, hasConsumers: true), "Disabled taps recover")
            expect(!EventTapPolicy.shouldReenable(type, hasConsumers: false), "Stopped taps stay stopped")
            expect(EventTapPolicy.mask(for: type) == 0, "Disable signals are never shifted into masks")
        }
        expect(!EventTapPolicy.shouldReenable(.keyDown, hasConsumers: true), "Ordinary input needs no recovery")
    }

    static func lifetimeTests() async {
        let hub = EventTapHub()
        let key = EventTapPolicy.mask(for: .keyDown)
        let mouse = EventTapPolicy.mask(for: .otherMouseDown)
        var received: [CGEventType] = []
        let first = hub.register(mask: key) { received.append($0.type) }
        expect(hub.consumerCount == 1 && !hub.isRunning, "No grant means no worker")
        expect(fixture.withLock { $0.records.isEmpty }, "Permission is checked before creating a tap")
        fixture.withLock { $0.trusted = true }
        hub.refreshPermission()
        await eventually { fixture.withLock { $0.records.count == 1 && $0.enabledCount == 1 } }
        let second = hub.register(mask: key) { received.append($0.type) }
        expect(fixture.withLock { $0.records.count == 1 }, "Shared mask reuses the tap")
        hub.remove(second)
        let third = hub.registerSynchronous(mask: mouse) { type, _ in
            fixture.withLock { $0.synchronousCount += 1 }
            return type == .otherMouseDown ? .swallow : .pass
        }
        await eventually { fixture.withLock { $0.records.count == 2 } }
        expect(fixture.withLock { $0.disabledCount == 1 }, "Rebuild stops the old tap first")
        let record = fixture.withLock { $0.records[1] }
        expect(record.mask == key | mouse, "Worker receives the merged mask")
        send([.keyDown, .keyDown, .otherMouseDown, .tapDisabledByTimeout, .tapDisabledByUserInput], through: record)
        await eventually { received.count == 2 && fixture.withLock { $0.synchronousCount == 1 && $0.enabledCount == 4 } }
        expect(received == [.keyDown, .keyDown], "Only matching main-actor handlers receive input")
        expect(fixture.withLock { $0.swallowedCount == 1 }, "Synchronous consumer swallows its event")
        hub.remove(third)
        await eventually { fixture.withLock { $0.records.count == 3 } }
        expect(hub.eventMask == key, "Removing a consumer shrinks the tap mask")
        hub.remove(first)
        expect(!hub.isRunning && hub.consumerCount == 0, "Last removal joins the worker")
        expect(fixture.withLock { $0.disabledCount == 3 }, "Every installed tap was torn down")
        fixture.withLock { $0.failNext = true }
        let retry = hub.register(mask: key) { _ in fatalError("Removed callback must not run") }
        await eventually { !hub.isRunning }
        hub.refreshPermission()
        await eventually { fixture.withLock { $0.records.count == 4 } }
        send([.keyDown], through: fixture.withLock { $0.records[3] })
        hub.remove(retry)
        await Task.yield()
        expect(hub.consumerCount == 0 && !hub.isRunning, "Queued callbacks cannot outlive removal")
        expect(!fixture.withLock { $0.wrongConfiguration }, "All taps use the private worker and session configuration")
        for _ in 0..<20 {
            let id = hub.register(mask: key) { _ in }
            hub.remove(id)
        }
        expect(!hub.isRunning, "Stopping during installation cannot leave a worker")
        fixture.withLock { $0.trusted = false }
        let denied = hub.register(mask: key) { _ in }
        hub.stop()
        hub.remove(denied)
        expect(hub.consumerCount == 0, "Bulk teardown and repeated removal are safe")
    }

    static func main() async {
        policyTests()
        await lifetimeTests()
        print("Passed \(checks) event-tap hub checks (no real taps or posted events)")
    }
}
