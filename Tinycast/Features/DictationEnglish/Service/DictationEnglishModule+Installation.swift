import AppKit
import Carbon.HIToolbox

extension DictationEnglishModule {
    convenience init(hub: EventTapHub, coordinator: DictationCoordinator) {
        let family = DictationFamily.shared
        family.bind(coordinator)
        family.installEnglish {
            NotchcastHost.current.showMessage(
                String(localized: "English translation failed; using the original transcript", table: "Notchcast"), .danger)
        }
        let swallowing = EventTapSubscription(hub: hub)
        self.init(register: { action in
            swallowing.startKeyPress(Int64(kVK_ANSI_Grave), skipsSynthetic: true) { event in
                Self.isFnGrave((event.getIntegerValueField(.keyboardEventKeycode), event.flags))
            }
            return hub.register(mask: EventTapPolicy.mask(for: .keyDown)) { event in
                guard !event.isSynthetic, !event.isRepeat, Self.isFnGrave((event.keyCode, event.flags))
                else { return }
                action()
            }
        }, remove: {
            hub.remove($0)
            swallowing.stop()
        }, toggle: { family.toggleEnglish() }, onStop: { family.cancelEnglish() })
    }

    nonisolated private static func isFnGrave(_ event: (keyCode: Int64, flags: CGEventFlags)) -> Bool {
        let other: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
        return event.keyCode == kVK_ANSI_Grave
            && event.flags.contains(.maskSecondaryFn) && event.flags.isDisjoint(with: other)
    }
}
