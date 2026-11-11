// notchcast-kit: host
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/ClearNotifications/Model/*.swift Tinycast/Features/ClearNotifications/Service/*.swift Tinycast/Features/ClearNotifications/ClearNotificationsModule*.swift
// notchcast-kit: command
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
import Foundation
import Synchronization

enum DialogTone { case neutral, danger }
enum NotchcastFeature { case clearNotifications }
@MainActor enum Permissions {
    static func isAccessibilityTrusted() -> Bool { true }
}
@MainActor final class AppCore {
    static let shared = AppCore()
    var messages: [String] = []
}

@main struct CommandTests {
    @MainActor static func main() async {
        let calls = Mutex(0)
        let module = ClearNotificationsModule(runner: ClearNotificationsRunner { _ in
            calls.withLock { $0 += 1 }
            return "7"
        })
        NotchcastHost.current.showMessage = { text, _ in AppCore.shared.messages.append(text) }
        module.start()
        let command = ClearNotificationsModule.launcherCommand
        precondition(command.feature == .clearNotifications && command.isEnabled())
        module.clearFromLauncher()
        await module.commandTask?.value
        precondition(calls.withLock { $0 } == 1)
        precondition(AppCore.shared.messages.last == "Notifications cleared: 7")
        module.stop()
        struct Unknown: Error {}
        let causes: [(any Error, String)] = [
            (ClearNotificationsFailure.accessibilityRequired, "Allow Accessibility access to clear notifications."),
            (ClearNotificationsFailure.automationRequired, "Allow Automation access to clear notifications."),
            (ClearNotificationsFailure.notificationCenterUnavailable, "Notification Center could not be opened."),
            (ClearNotificationsFailure.unreadable, "Notification Center could not be read."),
            (ClearNotificationsFailure.notificationsRemain, "Some notifications could not be cleared."),
            (ClearNotificationsFailure.invalidResult, "Could not clear notifications."),
            (ClearNotificationsFailure.preparationFailed, "Could not clear notifications."),
            (ClearNotificationsFailure.automationFailed(-50), "Could not clear notifications (error -50)."),
            (Unknown(), "Could not clear notifications."),
        ]
        for (failure, message) in causes {
            let failing = ClearNotificationsModule(runner: ClearNotificationsRunner { _ in throw failure })
            failing.start()
            failing.clearFromLauncher()
            await failing.commandTask?.value
            precondition(AppCore.shared.messages.last == message, "\(failure) reported \(AppCore.shared.messages.last ?? "")")
            failing.stop()
        }
        AppCore.shared.messages.removeLast(causes.count)
        module.clearFromLauncher()
        await module.commandTask?.value
        precondition(calls.withLock { $0 } == 1)
        precondition(AppCore.shared.messages.count == 1)
        let entries = ClearNotificationsModule.register(AppCore.shared)
        precondition(entries.count == 1 && entries[0].requires == [.clearNotifications] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === ClearNotificationsModule.shared)
        command.run()
        await ClearNotificationsModule.shared.commandTask?.value
        precondition(ClearNotificationsModule.shared.commandTask != nil && AppCore.shared.messages.count == 1)
        print("Verified launcher action reaches fake runner, reports count, refuses stopped module")
        print("Verified the command reaches the registered module, which refuses until started")
        print("Verified each failure reports its own message")
    }
}
