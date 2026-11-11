// notchcast-sources: Tinycast/Features/Torrents/Model/*.swift
// notchcast-sources: Tinycast/Features/Torrents/Service/*.swift
// notchcast-kit: platform core command
// notchcast-sources: Tinycast/Features/NetMerge/Model/*.swift
// notchcast-sources: Tinycast/Features/NetMerge/Service/*.swift
// notchcast-sources: Tinycast/Features/Torrents/Settings/TorrentJob+Presentation.swift
// notchcast-sources: Tinycast/Features/Torrents/Commands/*.swift
import AppKit

@MainActor final class AppCore {
    static let shared = AppCore()
    enum Tone { case danger }
    let appIndex = AppIndex()
    func showMessage(_ message: String, tone: Tone) {}
}
@MainActor final class AppIndex {
    var refreshes = 0
    func refreshNotchcastCommands() { refreshes += 1 }
}
@MainActor enum NotchcastCore {
    static let torrents = TorrentModule(session: TorrentAria2Session(stateDirectory: URL(filePath: "/unused")))
}
@MainActor final class FakeManager: TorrentQueueHost {
    var jobs: [TorrentJob] = []
    var inputs: [URL] = []
    var cancelled: [UUID] = []
    func enqueue(_ urls: [URL], keepSharing: Bool) -> [UUID] {
        inputs += urls
        return urls.map { _ in UUID() }
    }
    func cancel(_ id: UUID) { cancelled.append(id) }
    func tryAgain(_ id: UUID) -> UUID? { nil }
    func reveal(_ id: UUID) {}
    func stop() async {}
}
@main @MainActor struct TorrentCommandTests {
    static func main() async {
        let preferences = NotchcastPreferences.shared
        let original = preferences.isOn(.torrents)
        defer { preferences.set(.torrents, original) }
        let commands = TorrentCommands.launcherCommands
        preferences.set(.torrents, true)
        precondition(commands.allSatisfy { $0.isEnabled() })
        let before = AppCore.shared.appIndex.refreshes
        preferences.set(.torrents, false)
        for _ in 0..<100 { await Task.yield() }
        precondition(commands.allSatisfy { !$0.isEnabled() })
        precondition(AppCore.shared.appIndex.refreshes > before)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let magnet = "magnet:?xt=urn:btih:0123456789012345678901234567890123456789"
        board.setString(magnet + "\n/etc/no.torrent\nhttps://example.com/file.torrent\ninvalid", forType: .string)
        let urls = TorrentCommands.clipboardURLs(board)
        precondition(urls.count == 2)
        let manager = FakeManager()
        let accepted = await TorrentCommands.submit(urls, isEnabled: { true }, open: { manager.inputs.append($0); return true })
        precondition(accepted && manager.inputs == [URL(string: magnet)!])
        let rejected = await TorrentCommands.submit([URL(string: "magnet:?xt=bad")!],
                                                    isEnabled: { true }, open: { manager.inputs.append($0); return true })
        precondition(!rejected && manager.inputs.count == 1)
        let disabled = await TorrentCommands.submit([URL(string: magnet)!],
                                                    isEnabled: { false }, open: { manager.inputs.append($0); return true })
        precondition(!disabled && manager.inputs.count == 1)
        print("PASS: IDs, gating, refresh, clipboard filtering, submission validation and fake manager routing")
    }
}
