// notchcast-kit: core command
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift
import Foundation

@MainActor final class AppCore {
    static let shared = AppCore()
    var paletteCoordinator: AppCore { self }
    var isVisible = false
    func hidePalette(restoreFocus: Bool) {}
}
extension NotchcastCommandCatalog {
    nonisolated(unsafe) static var all: [NotchcastCommand] = []
}

@main struct CommandTests {
    @MainActor static var runs = 0
    @MainActor static func main() throws {
        // Preferences live in the dev app's domain; run in a throwaway home so a failure leaves nothing behind.
        if ProcessInfo.processInfo.environment["NC_SETTINGS_COMMANDS_HOME"] == nil {
            let home = FileManager.default.temporaryDirectory.appending(path: "nc-settings-commands-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: home) }
            let child = Process()
            child.executableURL = URL(filePath: CommandLine.arguments[0])
            child.environment = ProcessInfo.processInfo.environment.merging(
                ["NC_SETTINGS_COMMANDS_HOME": home.path, "HOME": home.path, "CFFIXED_USER_HOME": home.path]) { $1 }
            try child.run()
            child.waitUntilExit()
            exit(child.terminationStatus)
        }
        let preferences = NotchcastPreferences.shared
        let home = ProcessInfo.processInfo.environment["NC_SETTINGS_COMMANDS_HOME"]!
        precondition(NSHomeDirectory() == home, "preferences must stay in the throwaway home")
        for owner in NotchcastFeature.allCases {
            let slug = owner.rawValue
            var command = NotchcastCommand(slug: slug, name: slug, sfSymbol: "test", feature: owner, run: { runs += 1 })
            NotchcastCommandCatalog.all = [command]
            for feature in NotchcastFeature.allCases { preferences.set(feature, true) }
            preferences.set(owner, false)
            precondition(!NotchcastCommandCatalog.isEnabled(command.id))
            let before = runs
            precondition(NotchcastCommandCatalog.dispatch(command.id, dismiss: { preconditionFailure() }))
            precondition(runs == before)
            preferences.set(owner, true)
            precondition(NotchcastCommandCatalog.isEnabled(command.id))
            precondition(NotchcastCommandCatalog.dispatch(command.id, dismiss: {}))
            precondition(runs == before + 1)
            for dependency in owner.dependencies {
                preferences.set(dependency, false)
                precondition(!NotchcastCommandCatalog.isEnabled(command.id))
                preferences.set(dependency, true)
            }
            command.isEnabled = { false }
            NotchcastCommandCatalog.all = [command]
            precondition(!NotchcastCommandCatalog.isEnabled(command.id))
            command.feature = nil
            command.isEnabled = { true }
            NotchcastCommandCatalog.all = [command]
            precondition(!NotchcastCommandCatalog.isEnabled(command.id))
        }
        print("PASS: a command of each of \(NotchcastFeature.allCases.count) features; owner, dependency and runtime gates")
    }
}
