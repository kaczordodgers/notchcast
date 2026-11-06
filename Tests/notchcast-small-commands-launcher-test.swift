// notchcast-sources: Tinycast/Features/Launcher/SmallCommands/Model/*.swift Tinycast/Features/Launcher/SmallCommands/Service/*.swift Tinycast/Features/Launcher/SmallCommands/SmallCommandsModule*.swift
// notchcast-sources: Tinycast/Features/Launcher/CopyPath/Model/*.swift Tinycast/Features/Launcher/CopyPath/Service/*.swift
// notchcast-sources: Tinycast/Platform/AccessibilityText.swift
import Foundation

@MainActor protocol NotchcastModule {}
enum NotchcastFeature { case smallCommands }
struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
    var id: String { "command:nc-" + slug }
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    func isOn(_ feature: NotchcastFeature) -> Bool { true }
}
@MainActor enum NotchcastCore { static let smallCommands = SmallCommandsModule() }
@MainActor final class AppCore {
    enum Tone { case neutral }
    static let shared = AppCore()
    func showMessage(_ text: String, tone: Tone) {}
}
@main struct SmallTests {
    @MainActor static func main() async {
        precondition(SmallCommandsModule.argumentCount(entryID: SmallCommandsModule.shortenCommand.id) == 1)
        for command in [SmallCommandsModule.passwordCommand, SmallCommandsModule.noiseCommand,
                        SmallCommandsModule.airDropCommand] {
            precondition(SmallCommandsModule.argumentCount(entryID: command.id) == 0)
        }
        let module = SmallCommandsModule()
        module.start()
        var calls = 0
        var copied: [String] = []
        var reports: [String] = []
        for action in [SmallCommandsModule.Action.password, .shorten, .noise, .airDrop] {
            module.runFromLauncher(action, execute: { received in
                precondition(received == action)
                calls += 1
                switch received {
                case .password: return "fake-password"
                case .shorten: return "https://tinyurl.com/fake"
                case .noise, .airDrop: return nil
                }
            }, copy: { copied.append($0); return true }, report: { reports.append($0) })
            await module.commandTask?.value
        }
        precondition(calls == 4 && copied.count == 2 && reports == ["Copied", "Copied", "Done", "Done"])
        module.stop()
        module.runFromLauncher(.password, execute: { _ in preconditionFailure("Stopped") })
        precondition(module.commandTask == nil)
        print("Verified four launcher actions reach fake runners, copy text, report completion and stop")
    }
}
