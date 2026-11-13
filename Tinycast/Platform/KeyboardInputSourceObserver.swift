import AppKit
import Carbon.HIToolbox

enum KeyboardInputSourceObserver {
    @MainActor
    static func observe(_ action: @escaping @MainActor @Sendable () -> Void) -> NotificationToken {
        let center = DistributedNotificationCenter.default()
        return NotificationToken(center.addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { action() }
        }, center: center)
    }
}
