import AppKit
import Carbon.HIToolbox

extension DictationEnglishModule {
    convenience init(hub: EventTapHub, coordinator: DictationCoordinator) {
        let family = DictationFamily.shared
        family.bind(coordinator)
        family.installEnglish {
            AppCore.shared.showMessage(
                String(localized: "English translation failed; using the original transcript", table: "Notchcast"), tone: .danger)
        }
        let swallowing = EventTapSubscription(hub: hub)
        self.init(register: { action in
            swallowing.startKeyPress(Int64(kVK_ANSI_Grave), skipsSynthetic: true) { event in
                let other: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
                return event.flags.contains(.maskSecondaryFn) && event.flags.isDisjoint(with: other)
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
            swallowing.stop()
        }, toggle: { family.toggleEnglish() }, onStop: { family.cancelEnglish() })
    }
}
