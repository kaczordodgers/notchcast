// notchcast-sources: Tinycast/Features/ClearNotifications/Model/*.swift Tinycast/Features/ClearNotifications/Service/*.swift Tinycast/Features/ClearNotifications/ClearNotificationsModule*.swift
import Foundation
import Synchronization

@MainActor protocol NotchcastModule {}
enum NotchcastFeature { case clearNotifications }
struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}
@MainActor enum Permissions {
    static func isAccessibilityTrusted() -> Bool { true }
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    func isOn(_ feature: NotchcastFeature) -> Bool { true }
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
