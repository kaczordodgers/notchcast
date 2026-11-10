// notchcast-kit: core
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift
// notchcast-reads: notchcast/check-command-owners.py Tinycast/Features/**/*.swift
import Foundation

enum SettingsTab: Sendable { case notchcast }
struct AppEntry {
    enum Kind { case command }
    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    let kind: Kind
    let settingsOwner: SettingsTab?
    let symbolName: String
}
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
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = ["python3", "notchcast/check-command-owners.py"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        precondition(process.terminationStatus == 0)
        let rows = try JSONDecoder().decode([Row].self, from: data)
        precondition(!rows.isEmpty, "Every catalog command must retain owner gate coverage")
        let preferences = NotchcastPreferences.shared
        let home = ProcessInfo.processInfo.environment["NC_SETTINGS_COMMANDS_HOME"]!
        precondition(NSHomeDirectory() == home, "preferences must stay in the throwaway home")
        for row in rows {
            let owner = NotchcastFeature(rawValue: row.owner)!
            var command = NotchcastCommand(slug: row.id, name: row.id, sfSymbol: "test", feature: owner, run: { runs += 1 })
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
        print("PASS: \(rows.count) commands covered; catalog count \(rows.count); owner, dependency and runtime gates")
    }
    struct Row: Decodable { let id: String; let owner: String }
}
