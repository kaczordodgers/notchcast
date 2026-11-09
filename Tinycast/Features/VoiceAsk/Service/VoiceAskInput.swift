import ApplicationServices
import Foundation

@MainActor
final class VoiceAskInput {
    private let tap: EventTapSubscription
    private let module: VoiceAskModule
    private var heldKeys: Set<Int64> = []

    init(hub: EventTapHub, module: VoiceAskModule) {
        tap = EventTapSubscription(hub: hub)
        self.module = module
        module.onStart = { [weak self] in self?.start() }
        module.onStop = { [weak self] in self?.stop() }
    }

    private func start() {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown]
        tap.observe(mask: types.reduce(0) { $0 | (1 << $1.rawValue) }) { [weak self] event in
            guard let self, !event.isSynthetic, !event.isRepeat else { return }
            let alone = heldKeys.isEmpty
            if event.type == .keyDown { heldKeys.insert(event.keyCode) }
            if event.type == .keyUp { heldKeys.remove(event.keyCode) }
            if event.keyCode == module.keyCode, event.type == .keyDown {
                module.press(alone: alone && event.flags.isDisjoint(with: [.maskShift, .maskControl,
                    .maskAlternate, .maskCommand, .maskSecondaryFn]))
            } else if event.keyCode == module.keyCode, event.type == .keyUp {
                module.release()
            } else if event.type != .keyUp { module.chord() }
        }
    }

    private func stop() {
        tap.stop()
        heldKeys.removeAll()
    }
}
