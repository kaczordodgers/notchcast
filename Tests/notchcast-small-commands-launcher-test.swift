// notchcast-sources: Tinycast/Features/SmallCommands/Model/*.swift Tinycast/Features/SmallCommands/Service/*.swift Tinycast/Features/SmallCommands/SmallCommandsModule*.swift
// notchcast-sources: Tinycast/Features/CopyPath/Model/*.swift Tinycast/Features/CopyPath/Service/*.swift
// notchcast-sources: Tinycast/Platform/AccessibilityText.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-kit: host
import Foundation

enum DialogTone { case neutral }
enum NotchcastFeature { case smallCommands }
struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature
    var argumentCount = 0
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
    var id: String { "command:nc-" + slug }
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    func isOn(_ feature: NotchcastFeature) -> Bool { true }
}
@MainActor final class AppCore {}
@main struct SmallTests {
    @MainActor static func main() async {
        precondition(SmallCommandsModule.shortenCommand.argumentCount == 1)
        for command in [SmallCommandsModule.passwordCommand, SmallCommandsModule.noiseCommand,
                        SmallCommandsModule.airDropCommand] {
            precondition(command.argumentCount == 0)
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
        typealias Failure = SmallCommandsFailure
        precondition(SmallCommandsModule.failure(NoiseControlService.Outcome.switched(.off)) == nil)
        precondition(SmallCommandsModule.failure(AirDropService.Outcome.sent(1)) == nil)
        let causes: [(any Error, String)] = [
            (Failure.noLink, "No link to shorten."),
            (Failure.controlCenterNotRunning, "Control Center is not running."),
            (SmallCommandsModule.failure(NoiseControlService.Outcome.noAirPods)!, "No AirPods with noise control found."),
            (SmallCommandsModule.failure(NoiseControlService.Outcome.unchanged)!, "Noise control did not change."),
            (SmallCommandsModule.failure(AirDropService.Outcome.cancelled)!, "AirDrop was cancelled."),
            (SmallCommandsModule.failure(AirDropService.Outcome.noSelection)!, "Select files in Finder first."),
            (SmallCommandsModule.failure(AirDropService.Outcome.unavailable)!, "AirDrop is unavailable."),
            (NoiseControlService.Failure.needsAccessibility, "Allow Accessibility access to switch noise control."),
            (Failure.disabled, "Unavailable"),
            (AirDropService.Failure.busy, "Unavailable"),
        ]
        for (failure, message) in causes {
            reports = []
            module.runFromLauncher(.noise, execute: { _ in throw failure }, report: { reports.append($0) })
            await module.commandTask?.value
            precondition(reports == [message], "\(failure) reported \(reports)")
        }
        do {
            _ = try await module.perform(.shorten, frontAddress: { nil }, clipboard: { nil })
            preconditionFailure("shorten without a link must fail")
        } catch {
            precondition(error as? Failure == .noLink)
        }
        module.stop()
        var ranWhileStopped = false
        module.runFromLauncher(.password, execute: { _ in ranWhileStopped = true; return nil })
        for _ in 0..<20 { await Task.yield() }
        precondition(!ranWhileStopped)
        let entries = SmallCommandsModule.register(AppCore())
        precondition(entries.count == 1 && entries[0].requires == [.smallCommands] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === SmallCommandsModule.shared)
        print("Verified four launcher actions reach fake runners, copy text, report completion and stop")
        print("Verified each failure cause reports its own message")
    }
}
