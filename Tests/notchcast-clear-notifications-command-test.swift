// notchcast-kit: host
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/ClearNotifications/Model/*.swift Tinycast/Features/ClearNotifications/Service/*.swift Tinycast/Features/ClearNotifications/ClearNotificationsModule*.swift
import Foundation
import Synchronization

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
        NotchcastHost.current.showMessage = { text, _ in AppCore.shared.messages.append(text) }
        module.start()
        let command = ClearNotificationsModule.launcherCommand
        precondition(command.feature == .clearNotifications && command.isEnabled())
        module.clearFromLauncher()
        await module.commandTask?.value
        precondition(calls.withLock { $0 } == 1)
        precondition(AppCore.shared.messages.last == "Notifications cleared: 7")
        module.stop()
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
    }
}
