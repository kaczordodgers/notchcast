// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift
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
        let preferences = NotchcastPreferences.shared
        let domain = (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast"
        let defaults = UserDefaults(suiteName: domain)!
        let originalDomain = defaults.persistentDomain(forName: domain) ?? [:]
        let previous = Dictionary(uniqueKeysWithValues: NotchcastFeature.allCases.map { ($0, preferences.isOn($0)) })
        defer {
            for (feature, enabled) in previous { preferences.set(feature, enabled) }
            defaults.setPersistentDomain(originalDomain, forName: domain)
        }
        let bindings = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, "hotkey-" + $0.id) })
        let aliases = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, "alias-" + $0.id) })
        let snapshot = UserDefaults(suiteName: "nc-settings-commands-" + UUID().uuidString)!
        snapshot.set(bindings, forKey: "bindings")
        snapshot.set(aliases, forKey: "aliases")
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
            precondition(snapshot.dictionary(forKey: "bindings") as? [String: String] == bindings)
            precondition(snapshot.dictionary(forKey: "aliases") as? [String: String] == aliases)
        }
        print("PASS: \(rows.count) commands covered; catalog count \(rows.count); owner, dependency and runtime gates")
    }
    struct Row: Decodable { let id: String; let owner: String }
}
