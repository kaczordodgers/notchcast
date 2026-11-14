import AppKit

extension ShelfModule {
    private enum ClipboardFailure: Error { case tooManyFiles, folder }
    nonisolated static let showCommand = NotchcastCommand(slug: "show-shelf", name: String(localized: "Show Shelf", table: "Notchcast"), sfSymbol: "tray", feature: .shelfBetweenMacs, run: { SettingsActionCommands.show(.notchcastTwoMacs, .shelfBetweenMacs) })
    nonisolated static let sendCommand = clipboardCommand {
        NSPasteboard.general
    }

    nonisolated static func clipboardCommand(
        pasteboard: @escaping @MainActor @Sendable () -> NSPasteboard
    ) -> NotchcastCommand {
        NotchcastCommand(
        slug: "send-shelf-to-other-mac", name: String(localized: "Send Clipboard to Other Mac", table: "Notchcast"),
        sfSymbol: "paperplane", feature: .shelfBetweenMacs,
        run: {
            ShelfModule.shared.sendClipboard(pasteboard())
        })
    }

    func sendClipboard(_ pasteboard: NSPasteboard) {
        let files = PasteboardFiles.urls(on: pasteboard, limit: ShelfEngine.maximumItems + 1) { _ in true }
        let text = pasteboard.string(forType: .string)
        let link = NSURL(from: pasteboard) as URL?
        guard !files.isEmpty || text?.isEmpty == false || link != nil else {
            NotchcastHost.current.remoteResult(String(localized: "Clipboard is empty", table: "Notchcast"))
            return
        }
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            var sent = 0
            do {
                guard files.count <= ShelfEngine.maximumItems else { throw ClipboardFailure.tooManyFiles }
                let items = try await Self.clipboardItems(files: files, link: link, text: text)
                for item in items {
                    try await send(item)
                    sent += 1
                }
                guard !Task.isCancelled, isRunning, generation == token else { return }
                NotchcastHost.current.remoteResult(String(localized: "Sent Clipboard to Other Mac", table: "Notchcast"))
            } catch {
                guard !Task.isCancelled, isRunning, generation == token else { return }
                let message: String
                if sent > 0 {
                    message = String(localized: "Sent \(sent) of \(files.count) files to Other Mac", table: "Notchcast")
                } else {
                    switch error {
                    case ClipboardFailure.tooManyFiles:
                        message = String(localized: "Send at most 64 files at once", table: "Notchcast")
                    case ClipboardFailure.folder:
                        message = String(localized: "Folders cannot be sent to Other Mac", table: "Notchcast")
                    case ShelfEngine.Failure.oversized:
                        message = String(localized: "Each clipboard item must be 24 KiB or smaller", table: "Notchcast")
                    default:
                        message = String(localized: "Could Not Send Clipboard to Other Mac", table: "Notchcast")
                    }
                }
                NotchcastHost.current.remoteResult(message)
            }
        }
    }

    @concurrent
    private static func clipboardItems(files: [URL], link: URL?, text: String?) async throws -> [ShelfItem] {
        if !files.isEmpty {
            return try files.map { url in
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw ClipboardFailure.folder
                }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: ShelfEngine.maximumItemBytes + 1) ?? Data()
                guard data.count <= ShelfEngine.maximumItemBytes else { throw ShelfEngine.Failure.oversized }
                return ShelfItem(kind: .file, name: url.lastPathComponent, data: data)
            }
        }
        if let link, WebRules.isWebScheme(link.scheme) {
            return [ShelfItem(kind: .link, name: "Clipboard.url", data: Data(link.absoluteString.utf8))]
        }
        return [ShelfItem(kind: .text, name: "Clipboard.txt", data: Data((text ?? "").utf8))]
    }
}
