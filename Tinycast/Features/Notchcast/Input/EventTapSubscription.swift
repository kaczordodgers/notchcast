import ApplicationServices
import Foundation
import Synchronization

/// One feature's place on the shared tap; starting twice is a no-op and the hub owns permission.
@MainActor
final class EventTapSubscription {
    private let hub: EventTapHub
    private(set) var id: UUID?

    init(hub: EventTapHub) { self.hub = hub }

    isolated deinit { stop() }

    var isActive: Bool { id != nil }

    /// Runs on the tap thread: never wait for MainActor, retain the event, or do blocking work.
    func start(mask: CGEventMask, skipsSynthetic: Bool = false,
               handler: @escaping @Sendable (CGEventType, CGEvent) -> EventTapHub.Verdict) {
        guard id == nil else { return }
        id = hub.registerSynchronous(mask: mask) { type, event in
            guard !skipsSynthetic || !event.isSynthetic else { return .pass }
            return handler(type, event)
        }
    }

    /// `press` judges a key's first down only; its repeats and its release get the same verdict.
    func startKeyPress(_ keyCode: Int64, skipsSynthetic: Bool = false,
                       press: @escaping @Sendable (CGEvent) -> Bool) {
        let held = Mutex(false)
        start(mask: EventTapPolicy.mask(for: .keyDown) | EventTapPolicy.mask(for: .keyUp),
              skipsSynthetic: skipsSynthetic) { type, event in
            guard event.getIntegerValueField(.keyboardEventKeycode) == keyCode else { return .pass }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let swallow = held.withLock { held in
                guard type == .keyDown else {
                    defer { held = false }
                    return held
                }
                if !isRepeat { held = press(event) }
                return held
            }
            return swallow ? .swallow : .pass
        }
    }

    func observe(mask: CGEventMask, handler: @escaping @MainActor @Sendable (EventTapHub.Event) -> Void) {
        guard id == nil else { return }
        id = hub.register(mask: mask, handler: handler)
    }

    func stop() {
        guard let id else { return }
        self.id = nil
        hub.remove(id)
    }
}

extension CGEvent {
    var isSynthetic: Bool { getIntegerValueField(.eventSourceUserData) == Paster.tinycastEventTag }

    /// Tags an event a feature posts, so a `skipsSynthetic` tap never catches the feature's own key.
    func markSynthetic() { setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag) }
}
