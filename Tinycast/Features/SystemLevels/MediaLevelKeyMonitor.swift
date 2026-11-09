import AppKit
import Synchronization

@MainActor
final class MediaLevelKeyMonitor {
    typealias Operation = @MainActor () async -> SystemLevelsService.Result

    struct Press: Sendable {
        let key: MediaLevelKey
        let fine: Bool
        let modifiers: UInt64
        let location: CGPoint
        let isRepeat: Bool
    }

    private struct Pending {
        let press: Press
        let operation: Operation
    }

    private let tap: EventTapSubscription
    private let prepare: (Press) -> Operation
    private let applied: (LevelNotice) -> Void
    private let replay: @MainActor (Press) -> Void
    private var generation = UUID()
    private var enabled: Set<MediaLevelKey> = []
    private var pending: [Pending] = []
    private var worker: Task<Void, Never>?

    init(hub: EventTapHub, prepare: @escaping (Press) -> Operation,
         applied: @escaping (LevelNotice) -> Void,
         replay: @escaping @MainActor (Press) -> Void = MediaLevelKeyMonitor.replay) {
        tap = EventTapSubscription(hub: hub)
        self.prepare = prepare
        self.applied = applied
        self.replay = replay
    }

    func setEnabled(_ keys: Set<MediaLevelKey>) {
        guard enabled != keys else { return }
        stop()
        enabled = keys
        guard !keys.isEmpty else { return }
        let epoch = generation
        let policy = Mutex(MediaLevelKeyPolicy())
        var mask: CGEventMask = 1 << NSEvent.EventType.systemDefined.rawValue
        if keys.contains(.brightnessUp) || keys.contains(.brightnessDown) {
            mask |= (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        }
        tap.start(mask: mask, skipsSynthetic: true) { [weak self] type, event in
            let decoded = type.rawValue == NSEvent.EventType.systemDefined.rawValue
                ? NSEvent(cgEvent: event) : nil
            let decision = policy.withLock {
                if type == .keyDown || type == .keyUp {
                    return $0.decide(keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                                     isDown: type == .keyDown,
                                     isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                                     modifiers: event.flags.rawValue, enabled: keys)
                }
                guard let decoded else { return .pass }
                return $0.decide(subtype: Int(decoded.subtype.rawValue), data: decoded.data1,
                          modifiers: event.flags.rawValue, enabled: keys)
            }
            switch decision {
            case .pass: return .pass
            case .swallow: return .swallow
            case .press(let key, let fine):
                let press = Press(key: key, fine: fine, modifiers: event.flags.rawValue,
                                  location: event.location, isRepeat: type == .keyDown
                                    ? event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                                    : (decoded?.data1 ?? 0) & 1 != 0)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == epoch else { return }
                    self.enqueue(press)
                }
                return .swallow
            }
        }
    }

    func stop() {
        generation = UUID()
        tap.stop()
        enabled = []
        worker?.cancel()
        worker = nil
        pending = []
    }

    private func enqueue(_ press: Press) {
        let next = Pending(press: press, operation: prepare(press))
        if press.isRepeat, let last = pending.last, last.press.isRepeat, last.press.key == press.key {
            pending[pending.count - 1] = next
        } else {
            pending.append(next)
        }
        guard worker == nil else { return }
        let epoch = generation
        worker = Task { [weak self] in
            while let next = self?.takeNext(epoch) {
                let result = await next.operation()
                guard !Task.isCancelled, let self, self.generation == epoch else { return }
                switch result {
                case .applied(let notice): self.applied(notice)
                case .fallbackToNativeKeys: self.replay(next.press)
                case .cancelled: break
                }
            }
        }
    }

    private func takeNext(_ epoch: UUID) -> Pending? {
        guard generation == epoch, !Task.isCancelled else { return nil }
        guard !pending.isEmpty else { worker = nil; return nil }
        return pending.removeFirst()
    }

    static func replay(_ press: Press) {
        for event in nativeEvents(for: press) { event.post(tap: .cghidEventTap) }
    }

    static func nativeEvents(for press: Press) -> [CGEvent] {
        [0xA, 0xB].compactMap { state in
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(press.modifiers)), timestamp: 0,
                windowNumber: 0, context: nil, subtype: 8,
                data1: (press.key.rawValue << 16) | (state << 8), data2: -1)?.cgEvent
            event?.setIntegerValueField(.eventSourceUserData, value: Paster.tinycastEventTag)
            return event
        }
    }

    isolated deinit {
        worker?.cancel()
    }
}
