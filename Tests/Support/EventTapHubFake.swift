import ApplicationServices
import Foundation
import Observation

enum Paster { static let tinycastEventTag: Int64 = 0x54494E59 }

/// Stands in for the hub: it keeps what a feature registers and a harness delivers the events itself.
@MainActor
@Observable
final class EventTapHub {
    struct Event: Sendable {
        var type = CGEventType.null
        var location = CGPoint.zero
        var flags: CGEventFlags = []
        var keyCode: Int64 = 0
        var button: Int64 = 0
        var isRepeat = false
        var isSynthetic = false
        var timestamp: CGEventTimestamp = 0
    }

    enum Verdict: Sendable {
        case pass
        case swallow
    }

    typealias Handler = @MainActor @Sendable (Event) -> Void
    typealias SynchronousHandler = @Sendable (CGEventType, CGEvent) -> Verdict

    var isTrusted = false
    @ObservationIgnored private(set) var handlers: [UUID: Handler] = [:]
    @ObservationIgnored private(set) var synchronousHandlers: [UUID: SynchronousHandler] = [:]
    @ObservationIgnored private(set) var masks: [CGEventMask] = []
    @ObservationIgnored private(set) var registered = 0
    @ObservationIgnored private(set) var removals = 0
    @ObservationIgnored private(set) var refreshes = 0

    var consumerCount: Int { handlers.count + synchronousHandlers.count }
    var handler: SynchronousHandler? { synchronousHandlers.values.first }

    @discardableResult
    func register(mask: CGEventMask, handler: @escaping Handler) -> UUID {
        let id = add(mask)
        handlers[id] = handler
        return id
    }

    @discardableResult
    func registerSynchronous(mask: CGEventMask, handler: @escaping SynchronousHandler) -> UUID {
        let id = add(mask)
        synchronousHandlers[id] = handler
        return id
    }

    func remove(_ id: UUID) {
        removals += 1
        handlers[id] = nil
        synchronousHandlers[id] = nil
    }

    func refreshPermission() { refreshes += 1 }

    func send(_ event: Event) {
        for handler in handlers.values { handler(event) }
    }

    func send(_ type: CGEventType, key: Int, flags: CGEventFlags = [], at time: TimeInterval,
              isRepeat: Bool = false, isSynthetic: Bool = false) {
        send(Event(type: type, flags: flags, keyCode: Int64(key), isRepeat: isRepeat,
                   isSynthetic: isSynthetic, timestamp: UInt64(time * 1_000_000_000)))
    }

    private func add(_ mask: CGEventMask) -> UUID {
        precondition(mask != 0, "The real hub refuses an empty mask")
        masks.append(mask)
        registered += 1
        return UUID()
    }
}
