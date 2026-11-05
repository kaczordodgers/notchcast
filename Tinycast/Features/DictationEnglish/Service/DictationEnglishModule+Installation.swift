import AppKit
import Carbon.HIToolbox
import Synchronization

extension DictationEnglishModule {
    convenience init(hub: EventTapHub, coordinator: DictationCoordinator) {
        DictationCoordinator.englishTranscriptStage = { raw, language in
            let translated = await DictationEnglish.process(raw, language: language) {
                await MainActor.run {
                    AppCore.shared.showMessage(
                        String(localized: "English translation failed; using the original transcript", table: "Notchcast"), tone: .danger)
                }
            }
            await DictationCleanup.observeTranscript(raw: raw, cleaned: translated)
            return translated
        }
        var synchronous: UUID?
        self.init(register: { action in
            let held = Mutex(false)
            synchronous = hub.registerSynchronous(mask:
                EventTapPolicy.mask(for: .keyDown) | EventTapPolicy.mask(for: .keyUp)) { type, event in
                guard event.getIntegerValueField(.eventSourceUserData) != Paster.tinycastEventTag,
                      event.getIntegerValueField(.keyboardEventKeycode) == kVK_ANSI_Grave
                else { return .pass }
                return held.withLock { down in
                    if type == .keyUp {
                        let swallow = down
                        down = false
                        return swallow ? .swallow : .pass
                    }
                    let other: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
                    down = event.flags.contains(.maskSecondaryFn) && event.flags.isDisjoint(with: other)
                    return down ? .swallow : .pass
                }
            }
            return hub.register(mask: EventTapPolicy.mask(for: .keyDown)) { event in
                let other: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
                guard !event.isSynthetic, !event.isRepeat,
                      event.keyCode == kVK_ANSI_Grave,
                      event.flags.contains(.maskSecondaryFn), event.flags.isDisjoint(with: other)
                else { return }
                action()
            }
        }, remove: {
            hub.remove($0)
            if let synchronous { hub.remove(synchronous) }
            synchronous = nil
        }, toggle: { [weak coordinator] in
            guard let coordinator else { return }
            if coordinator.triggerIsRecording {
                coordinator.triggerFinished()
            } else {
                coordinator.triggerStarted(inEnglish: true)
            }
        }, onStop: { [weak coordinator] in coordinator?.cancelEnglish() })
    }
}
