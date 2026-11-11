// notchcast-sources: Tinycast/Features/Archives/Model/*.swift Tinycast/Features/Archives/Service/*.swift
// notchcast-kit: host
// notchcast-sources: Tinycast/Features/Archives/ArchiveModule.swift Tinycast/Features/Archives/Commands/*.swift
// notchcast-kit: core platform command
import AppKit

@MainActor final class AppCore {
    static let shared = AppCore()
    let appIndex = AppIndex()
    var messages: [String] = []
}
@MainActor final class AppIndex {
    var refreshes = 0
    func refreshNotchcastCommands() { refreshes += 1 }
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
        NotchcastHost.current.showMessage = { text, _ in AppCore.shared.messages.append(text) }
        NotchcastHost.current.refreshNotchcastCommands = { AppCore.shared.appIndex.refreshNotchcastCommands() }
        preferences.set(.archives, true)
        ArchiveCompressionCommands.submit([], format: .zip)
        precondition(AppCore.shared.messages.last == "The archive engine is not running.")
        ArchiveModule.shared.start()
        ArchiveCompressionCommands.submit([], format: .small)
        precondition(AppCore.shared.messages.last == "No files selected in Finder.")
        struct NoFinder: Error {}
        NotchcastHost.current.finderSelection = { throw NoFinder() }
        let reported = AppCore.shared.messages.count
        ArchiveCompressionCommands.run(.zip)
        for _ in 0..<1000 where AppCore.shared.messages.count == reported { await Task.yield() }
        precondition(AppCore.shared.messages.last == "Couldn’t read the Finder selection.", "run reads the host's Finder selection")
        NotchcastHost.current.finderSelection = { [] }
        preferences.set(.archives, false)
        ArchiveCompressionCommands.run(.fast)
        precondition(AppCore.shared.messages.last == "The archive engine is not running.")
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
        let refreshes = AppCore.shared.appIndex.refreshes
        preferences.set(.archives, false)
        for _ in 0..<100 { await Task.yield() }
        precondition(commands.allSatisfy { !$0.isEnabled() })
        precondition(AppCore.shared.appIndex.refreshes > refreshes)
        precondition(ArchiveCommands.submit([archive], to: module) == nil)
        precondition(module.queue.jobs.count == 2)
        module.stop()
        preferences.set(.archives, true)
        ArchiveCommands.cancelAll(in: module)
        precondition(AppCore.shared.messages.last == "The archive engine is not running.")
        print("PASS: switch gating, index refresh, module routing, unsupported/empty input and cancellation")
    }
}
