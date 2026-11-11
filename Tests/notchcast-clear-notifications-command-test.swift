// notchcast-sources: Tinycast/Features/ClearNotifications/Model/*.swift Tinycast/Features/ClearNotifications/Service/*.swift Tinycast/Features/ClearNotifications/ClearNotificationsModule*.swift
// notchcast-kit: command
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
import Foundation
import Synchronization

@MainActor protocol NotchcastModule {}
enum NotchcastFeature { case clearNotifications }
@MainActor enum Permissions {
    static func isAccessibilityTrusted() -> Bool { true }
}
@MainActor enum NotchcastCore {
    static var clearNotifications = ClearNotificationsModule()
}
@MainActor final class AppCore {
    enum Tone { case neutral, danger }
    static let shared = AppCore()
    var messages: [String] = []
    func showMessage(_ text: String, tone: Tone) { messages.append(text) }
}

@main struct CommandTests {
    @MainActor static func main() async {
        let calls = Mutex(0)
        let module = ClearNotificationsModule(runner: ClearNotificationsRunner { _ in
            calls.withLock { $0 += 1 }
            return "7"
        })
        NotchcastCore.clearNotifications = module
        module.start()
        let command = ClearNotificationsModule.launcherCommand
        precondition(command.feature == .clearNotifications && command.isEnabled())
        command.run()
        await module.commandTask?.value
        precondition(calls.withLock { $0 } == 1)
        precondition(AppCore.shared.messages.last == "Notifications cleared: 7")
        module.stop()
        command.run()
        await module.commandTask?.value
        precondition(calls.withLock { $0 } == 1)
        precondition(AppCore.shared.messages.count == 1)
        print("Verified command reaches fake runner, reports count, refuses stopped module")
    }
}
