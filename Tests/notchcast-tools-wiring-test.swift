// notchcast-sources: Tinycast/Features/Notchcast/Tools/NotchcastToolsCommands.swift
// notchcast-sources: Tinycast/Features/Notchcast/Tools/NotchcastToolsLauncherCommands.swift
// notchcast-kit: core command
// notchcast-sources: Tinycast/Features/CommandRunner/Model/HostCommandCatalog.swift
// notchcast-sources: Tinycast/Features/CommandRunner/Service/HostCommandProfile.swift
import Foundation

@main @MainActor struct ToolsWiringTest {
    static func main() async throws {
        let suite = "tools-wiring-\(UUID())"
        let preferences = NotchcastPreferences(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        var reads = 0
        var runs: [NotchcastToolsCommands.Action] = []
        var messages: [String] = []
        var refreshes = 0
        var files = [URL(fileURLWithPath: "/synthetic/input.png")]
        let controller = NotchcastToolsCommands(preferences: preferences, selection: {
            reads += 1; return files
        }, post: { messages.append($0) }, refresh: { refreshes += 1 }) { action, _, valid in
            if valid() { runs.append(action) }
        }
        NotchcastToolsLauncherCommands.controller = controller
        controller.start()
        let commands = NotchcastToolsLauncherCommands.all
        precondition(commands.count == 8)
        for (action, command) in zip(NotchcastToolsCommands.Action.allCases, commands) {
            preferences.set(action.feature, false)
            let before = reads
            precondition(!command.isEnabled())
            command.run()
            await controller.settle()
            precondition(reads == before && !runs.contains(action))
            preferences.set(action.feature, true)
            precondition(command.isEnabled())
            command.run()
            await controller.settle()
            precondition(runs.last == action)
            preferences.set(action.feature, false)
        }
        for _ in 0..<20 { await Task.yield() }
        precondition(refreshes > 1)
        preferences.set(.mediaTools, true)
        files = []
        let before = runs.count
        controller.perform(.compressImage)
        await controller.settle()
        precondition(runs.count == before && messages.last == "No files selected in Finder.")
        controller.perform(.makeGIF)
        preferences.set(.mediaTools, false)
        await controller.settle()
        precondition(runs.count == before)
        controller.stop()
        precondition(commands.allSatisfy { !$0.isEnabled() })
        var staleApplied = false
        preferences.set(.mediaTools, true)
        let suspended = NotchcastToolsCommands(preferences: preferences, selection: {
            [URL(fileURLWithPath: "/synthetic/input.png")]
        }, post: { _ in }, refresh: {}) { action, _, valid in
            preferences.set(action.feature, false)
            preferences.set(action.feature, true)
            await Task.yield()
            staleApplied = valid()
        }
        suspended.start()
        suspended.perform(.makeGIF)
        await suspended.settle()
        precondition(!staleApplied)
        suspended.stop()
        var unrelatedApplied = false
        let unrelated = NotchcastToolsCommands(preferences: preferences, selection: { [] },
            post: { _ in }, refresh: {}) { _, _, valid in
                preferences.set(.mediaTools, !preferences.isOn(.mediaTools))
                await Task.yield()
                unrelatedApplied = valid()
            }
        preferences.set(.commandRunner, true)
        unrelated.start()
        unrelated.perform(.listCommands)
        await unrelated.settle()
        precondition(unrelatedApplied)
        unrelated.stop()
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "profile.json")
        let missing = await HostCommandProfile.load(file: file, host: "test-host")
        precondition(missing.isEmpty)
        try Data("invalid".utf8).write(to: file)
        let invalid = await HostCommandProfile.load(file: file, host: "test-host")
        precondition(invalid.isEmpty)
        let entry = HostCommandCatalog.Entry(id: "fake", title: "Fake", executable: "/synthetic/tool")
        try JSONEncoder().encode([entry]).write(to: file)
        let loaded = await HostCommandProfile.load(file: file, host: "test-host")
        precondition(loaded == [entry])
        print("Tools wiring passed")
    }
}
