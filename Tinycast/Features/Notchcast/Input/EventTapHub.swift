import ApplicationServices
import Foundation
import Observation

@MainActor
@Observable
final class EventTapHub {
    static let shared = EventTapHub()

    struct Event: Sendable {
        let type: CGEventType
        let location: CGPoint
        let flags: CGEventFlags
        let keyCode: Int64
        let button: Int64
        let isRepeat: Bool
        let isSynthetic: Bool
        let timestamp: CGEventTimestamp

        nonisolated init(type: CGEventType, event: CGEvent) {
            self.type = type
            location = event.location
            flags = event.flags
            keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            button = event.getIntegerValueField(.mouseEventButtonNumber)
            isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            isSynthetic = event.getIntegerValueField(.eventSourceUserData) == Paster.tinycastEventTag
            timestamp = event.timestamp
        }
    }

    enum Verdict: Sendable {
        case pass
        case swallow
    }

    typealias Handler = @MainActor @Sendable (Event) -> Void
    typealias SynchronousHandler = @Sendable (CGEventType, CGEvent) -> Verdict

    /// Accessibility trust as last read; rechecked every second while anything is registered.
    private(set) var isTrusted = false
    @ObservationIgnored private var policy = EventTapPolicy()
    @ObservationIgnored private var handlers: [UUID: Handler] = [:]
    @ObservationIgnored private var synchronousHandlers: [UUID: SynchronousHandler] = [:]
    @ObservationIgnored private var order: [UUID] = []
    @ObservationIgnored private var session: EventTapThread?
    @ObservationIgnored private var permissionWatch: Task<Void, Never>?

    isolated deinit {
        permissionWatch?.cancel()
        session?.stop()
    }

    var consumerCount: Int { policy.consumers.count }
    var eventMask: CGEventMask { policy.mask }
    var isRunning: Bool { session?.isRunning == true }

    @discardableResult
    func register(mask: CGEventMask, handler: @escaping Handler) -> UUID {
        let id = UUID()
        handlers[id] = handler
        add(id, mask: mask)
        return id
    }

    /// Runs on the tap thread: never wait for MainActor, retain the event, or do blocking work.
    @discardableResult
    func registerSynchronous(mask: CGEventMask, handler: @escaping SynchronousHandler) -> UUID {
        let id = UUID()
        synchronousHandlers[id] = handler
        add(id, mask: mask)
        return id
    }

    func remove(_ id: UUID) {
        policy.remove(id)
        handlers.removeValue(forKey: id)
        synchronousHandlers.removeValue(forKey: id)
        order.removeAll { $0 == id }
        reconcile()
    }

    func stop() {
        for id in order { policy.remove(id) }
        handlers.removeAll()
        synchronousHandlers.removeAll()
        order.removeAll()
        reconcile()
    }

    /// Restarts a tap that failed to start; reading trust never opens an Accessibility prompt.
    func refreshPermission() {
        reconcile()
    }

    private func add(_ id: UUID, mask: CGEventMask) {
        precondition(mask != 0)
        policy.register(id, mask: mask)
        order.append(id)
        reconcile()
    }

    private func reconcile() {
        watchPermission()
        guard policy.needsTap, readTrust() else {
            session?.stop()
            session = nil
            return
        }
        let consumers = order.compactMap { id -> EventTapThread.Consumer? in
            guard let mask = policy.consumers[id] else { return nil }
            return EventTapThread.Consumer(id: id, mask: mask, handler: synchronousHandlers[id])
        }
        let options = EventTapPolicy.options(hasSynchronousConsumers: !synchronousHandlers.isEmpty)
        if let session, session.mask == policy.mask, session.options == options, session.isRunning {
            session.update(consumers)
            return
        }
        session?.stop()
        let generation = UUID()
        let worker = EventTapThread(
            id: generation, mask: policy.mask, options: options, consumers: consumers
        ) { [weak self] event, ids in
            // One FIFO preserves event order without moving a CGEvent across isolation boundaries.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.session?.id == generation else { return }
                for id in ids { self.handlers[id]?(event) }
            }
        }
        session = worker
        worker.start()
    }

    private func readTrust() -> Bool {
        let trusted = AXIsProcessTrusted()
        if isTrusted != trusted { isTrusted = trusted }
        return trusted
    }

    // macOS announces neither a grant nor a revocation, so trust is polled while a tap is wanted.
    private func watchPermission() {
        guard policy.needsTap else {
            permissionWatch?.cancel()
            permissionWatch = nil
            return
        }
        guard permissionWatch == nil else { return }
        permissionWatch = Task { [weak self] in
            while true {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self else { return }
                let trusted = isTrusted
                if readTrust() != trusted { reconcile() }
            }
        }
    }
}
