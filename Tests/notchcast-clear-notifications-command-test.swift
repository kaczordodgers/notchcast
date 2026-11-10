// notchcast-sources: Tinycast/Features/ClearNotifications/Model/*.swift Tinycast/Features/ClearNotifications/Service/*.swift
// notchcast-sources: Tinycast/Features/ClearNotifications/ClearNotificationsModule.swift
// notchcast-sources: Tinycast/Features/ClearNotifications/ClearNotificationsModule+Command.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
import Foundation
import Synchronization

@MainActor protocol NotchcastModule {}
enum DialogTone { case neutral, danger }
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
extension ClearNotificationsModule {
    static var shared = ClearNotificationsModule()
}

@main struct CommandTests {
    @MainActor static func main() async {
        var messages: [String] = []
        NotchcastHost.current.showMessage = { text, _ in messages.append(text) }
        let calls = Mutex(0)
        let module = ClearNotificationsModule(runner: ClearNotificationsRunner { _ in
            calls.withLock { $0 += 1 }
            return "7"
        })
        ClearNotificationsModule.shared = module
        module.start()
        let command = ClearNotificationsModule.launcherCommand
        precondition(command.feature == .clearNotifications && command.isEnabled())
        command.run()
        await module.commandTask?.value
        precondition(calls.withLock { $0 } == 1)
        precondition(messages.last == "Notifications cleared: 7")
        module.stop()
        command.run()
        await module.commandTask?.value
        precondition(calls.withLock { $0 } == 1)
        precondition(messages.count == 1)
        print("Verified command reaches fake runner, reports count, refuses stopped module")
    }
}
