import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
enum TorrentCommands {
    nonisolated static let launcherCommands: [NotchcastCommand] = [
        downloadClipboardCommand, openFileCommand, cancelAllCommand
    ]
    nonisolated static let downloadClipboardCommand =
        NotchcastCommand(slug: "download-torrent-from-clipboard",
                         name: String(localized: "Download Torrent from Clipboard"),
                         sfSymbol: "arrow.down.doc", isEnabled: { enabled }, run: { downloadClipboard() })
    nonisolated static let openFileCommand =
        NotchcastCommand(slug: "open-torrent-file", name: String(localized: "Open Torrent File…"),
                         sfSymbol: "doc", isEnabled: { enabled }, run: { openFile() })
    nonisolated static let cancelAllCommand =
        NotchcastCommand(slug: "cancel-all-torrents", name: String(localized: "Cancel All Torrents"),
                         sfSymbol: "xmark.circle", isEnabled: { enabled }, run: { cancelAll() })

    private static let availability = TorrentCommandAvailability()
    static var enabled: Bool {
        _ = availability
        return NotchcastPreferences.shared.isOn(.torrents)
    }

    static func clipboardURLs(_ pasteboard: NSPasteboard) -> [URL] {
        var urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        if let text = pasteboard.string(forType: .string) {
            for line in text.components(separatedBy: .newlines) {
                let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if value.hasPrefix("/") { urls.append(URL(filePath: value)) } else if
                    let url = URL(string: value), url.scheme != nil { urls.append(url) }
            }
        }
        return Array(Set(urls.filter { TorrentModule.accepts($0) }))
    }

    static func submit(_ urls: [URL], to manager: any TorrentQueueHost,
                       isEnabled: () -> Bool, keepSharing: () -> Bool) async -> Bool {
        var valid: [URL] = []
        for url in urls {
            if (try? await TorrentSubmission.read(url)) != nil { valid.append(url) }
            guard !Task.isCancelled else { return false }
        }
        guard isEnabled(), !valid.isEmpty else { return false }
        return !manager.enqueue(valid, keepSharing: keepSharing()).isEmpty
    }

    private static func downloadClipboard() {
        guard enabled else { return }
        download(clipboardURLs(.general))
    }

    private static func openFile() {
        guard enabled else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(importedAs: "org.bittorrent.torrent")]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK, enabled else { return }
            download(panel.urls)
        }
    }

    private static func download(_ urls: [URL]) {
        Task {
            let accepted = await submit(urls, to: NotchcastCore.torrents.manager,
                                        isEnabled: { enabled && NotchcastCore.torrents.isRunning },
                                        keepSharing: { NotchcastPreferences.shared.isOn(.torrentsKeepSharing) })
            guard enabled, !Task.isCancelled, !accepted else { return }
            AppCore.shared.showMessage(String(localized: "No usable torrent link or file was found."), tone: .danger)
        }
    }

    static func cancelAll(in manager: any TorrentQueueHost) {
        for job in manager.jobs where job.state.isRunning { manager.cancel(job.id) }
    }

    private static func cancelAll() {
        guard enabled else { return }
        cancelAll(in: NotchcastCore.torrents.manager)
    }
}
