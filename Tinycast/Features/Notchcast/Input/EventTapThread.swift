import ApplicationServices
import Foundation
import Synchronization
import os

// Copies CommandEscapeTap.Session's worker pattern; its fileprivate scope prevents reuse.
final class EventTapThread: Sendable {
    struct Consumer: Sendable {
        let id: UUID
        let mask: CGEventMask
        let handler: EventTapHub.SynchronousHandler?
    }

    // CF run-loop control is thread-safe; the port is used only by its worker.
    private struct Installation: @unchecked Sendable {
        let runLoop: CFRunLoop
        let port: CFMachPort
    }

    private struct State {
        var active = true
        var installation: Installation?
        var consumers: [Consumer]
    }

    let id: UUID
    let mask: CGEventMask
    let options: CGEventTapOptions
    private let logger = Logger(subsystem: "com.tinycast", category: "EventTapHub")
    private let state: Mutex<State>
    private let finished = DispatchSemaphore(value: 0)
    private let onEvent: @Sendable (EventTapHub.Event, [UUID]) -> Void

    init(
        id: UUID, mask: CGEventMask, options: CGEventTapOptions, consumers: [Consumer],
        onEvent: @escaping @Sendable (EventTapHub.Event, [UUID]) -> Void
    ) {
        self.id = id
        self.mask = mask
        self.options = options
        state = Mutex(State(consumers: consumers))
        self.onEvent = onEvent
    }

    var isRunning: Bool { state.withLock { $0.active } }

    func update(_ consumers: [Consumer]) {
        state.withLock { $0.consumers = consumers }
    }

    func start() {
        let thread = Thread { self.run() }
        thread.name = "notchcast.input-events"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    func stop() {
        state.withLock { state in
            state.active = false
            guard let runLoop = state.installation?.runLoop else { return }
            // Queue the stop so teardown also works before CFRunLoopRun has entered.
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(runLoop)
        }
        finished.wait()
        finished.signal()
    }

    private func run() {
        autoreleasepool {
            defer {
                state.withLock {
                    $0.active = false
                    $0.installation = nil
                }
                finished.signal()
            }
            guard isRunning, AXIsProcessTrusted(),
                let port = CGEvent.tapCreate(
                    tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
                    eventsOfInterest: mask, callback: Self.callback,
                    userInfo: Unmanaged.passUnretained(self).toOpaque())
            else { return }
            defer {
                CGEvent.tapEnable(tap: port, enable: false)
                CFMachPortInvalidate(port)
            }
            guard let source = CFMachPortCreateRunLoopSource(nil, port, 0),
                let runLoop = CFRunLoopGetCurrent()
            else { return }
            CFRunLoopAddSource(runLoop, source, .defaultMode)
            defer { CFRunLoopRemoveSource(runLoop, source, .defaultMode) }
            let shouldRun = state.withLock { state in
                guard state.active else { return false }
                state.installation = Installation(runLoop: runLoop, port: port)
                return true
            }
            guard shouldRun else { return }
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
        }
    }

    private func receive(type: CGEventType, event: CGEvent) -> Bool {
        if EventTapPolicy.shouldReenable(type, hasConsumers: isRunning) {
            state.withLock { state in
                guard state.active, let port = state.installation?.port else { return }
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return false
        }
        return state.withLock { state in
            guard state.active else { return false }
            let eventMask = EventTapPolicy.mask(for: type)
            var swallowed = false
            var observers: [UUID] = []
            for consumer in state.consumers where consumer.mask & eventMask != 0 {
                if let handler = consumer.handler {
                    let start = ContinuousClock.now
                    if handler(type, event) == .swallow { swallowed = true }
                    let elapsed = start.duration(to: .now)
                    if elapsed > .milliseconds(5) {
                        logger.warning(
                            "Synchronous event handler \(consumer.id) took \(String(describing: elapsed), privacy: .public)")
                    }
                } else {
                    observers.append(consumer.id)
                }
            }
            if !observers.isEmpty { onEvent(EventTapHub.Event(type: type, event: event), observers) }
            return swallowed
        }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let worker = Unmanaged<EventTapThread>.fromOpaque(context).takeUnretainedValue()
        return worker.receive(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
    }
}
