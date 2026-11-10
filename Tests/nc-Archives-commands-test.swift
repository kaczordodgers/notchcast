// notchcast-sources: Tinycast/Features/Archives/Model/*.swift Tinycast/Features/Archives/Service/*.swift
// notchcast-sources: Tinycast/Features/Archives/ArchiveModule.swift Tinycast/Features/Archives/Commands/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-kit: platform
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
import AppKit

enum SettingsTab: Sendable { case notchcast }
struct AppEntry: Sendable {
    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    enum Kind: Sendable { case command }
    let kind: Kind
    let settingsOwner: SettingsTab?
    let symbolName: String?
}
enum DialogTone { case danger }
extension ArchiveModule {
    static let shared = ArchiveModule(preferences: .shared)
}
@MainActor final class FakeDefaults: ArchiveDefaultApplicationSetting {
    func setEnabled(_ enabled: Bool, application: URL) async throws {}
}
struct MissingTool: ArchiveToolLocating {
    func locate() -> URL? { nil }
}

@main @MainActor struct ArchiveCommandTests {
    static func main() async {
        let preferences = NotchcastPreferences.shared
        let original = preferences.isOn(.archives)
        defer { preferences.set(.archives, original) }
        let suite = "archive-commands.\(UUID())"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let local = NotchcastPreferences(suiteName: suite)
        let module = ArchiveModule(preferences: local, locator: MissingTool(), defaultApplications: FakeDefaults())
        let commands = [ArchiveCommands.extractCommand, ArchiveCommands.cancelCommand]
        var messages: [String] = []
        var refreshes = 0
        NotchcastHost.current.showMessage = { text, _ in messages.append(text) }
        NotchcastHost.current.refreshNotchcastCommands = { refreshes += 1 }
        preferences.set(.archives, true)
        ArchiveCompressionCommands.submit([], format: .zip)
        precondition(messages.last == "The archive engine is not running.")
        ArchiveModule.shared.start()
        ArchiveCompressionCommands.submit([], format: .small)
        precondition(messages.last == "No files selected in Finder.")
        preferences.set(.archives, false)
        ArchiveCompressionCommands.run(.fast)
        precondition(messages.last == "The archive engine is not running.")
        ArchiveModule.shared.stop()
        preferences.set(.archives, true)
        precondition(commands.allSatisfy { $0.isEnabled() })
        precondition(ArchiveCommands.submit([], to: module) == "The archive engine is not running.")
        module.start()
        precondition(ArchiveCommands.submit([], to: module) == "No archive was selected.")
        precondition(ArchiveCommands.submit([URL(filePath: "/fixture/no.txt")], to: module) != nil)
        precondition(ArchiveCommands.submit([URL(string: "https://example.invalid/a.zip")!], to: module) != nil)
        precondition(module.queue.jobs.isEmpty)
        let archive = URL(filePath: "/fixture/a.zip")
        precondition(ArchiveCommands.submit([archive], to: module) == nil)
        precondition(module.queue.jobs.first?.archive == archive)
        precondition(module.queue.jobs.first?.mode == .keepArchive)
        local.set(.archivesInPlace, true)
        precondition(ArchiveCommands.submit([URL(filePath: "/fixture/b.zip")], to: module) == nil)
        precondition(module.queue.jobs.last?.mode == .inPlace)
        ArchiveCommands.cancelAll(in: module)
        precondition(module.queue.jobs.map(\.state) == [.cancelling, .cancelled])
        await module.queue.waitUntilIdle()
        precondition(module.isRunning && module.queue.jobs.last?.state == .cancelled)
        precondition(module.queue.jobs.first?.state == .cancelled || module.queue.jobs.first?.state == .failed)
        let refreshesBefore = refreshes
        preferences.set(.archives, false)
        for _ in 0..<100 { await Task.yield() }
        precondition(commands.allSatisfy { !$0.isEnabled() })
        precondition(refreshes > refreshesBefore)
        precondition(ArchiveCommands.submit([archive], to: module) == nil)
        precondition(module.queue.jobs.count == 2)
        module.stop()
        preferences.set(.archives, true)
        ArchiveCommands.cancelAll(in: module)
        precondition(messages.last == "The archive engine is not running.")
        print("PASS: switch gating, index refresh, module routing, unsupported/empty input and cancellation")
    }
}
