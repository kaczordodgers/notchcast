import AppKit

extension ShelfModule {
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
        let files = PasteboardFiles.urls(on: pasteboard)
        let text = pasteboard.string(forType: .string)
        let link = NSURL(from: pasteboard) as URL?
        guard !files.isEmpty || text?.isEmpty == false || link != nil else {
            NotchcastHost.current.remoteResult(String(localized: "Clipboard is empty", table: "Notchcast"))
            return
        }
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            do {
                let items = try await Self.clipboardItems(files: files, link: link, text: text)
                for item in items { try await send(item) }
                guard !Task.isCancelled, isRunning, generation == token else { return }
                NotchcastHost.current.remoteResult(String(localized: "Sent Clipboard to Other Mac", table: "Notchcast"))
            } catch {
                guard !Task.isCancelled, isRunning, generation == token else { return }
                NotchcastHost.current.remoteResult(String(localized: "Could Not Send Clipboard to Other Mac", table: "Notchcast"))
            }
        }
    }

    @concurrent
    private static func clipboardItems(files: [URL], link: URL?, text: String?) async throws -> [ShelfItem] {
        if !files.isEmpty {
            return try files.map { url in
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= ShelfEngine.maximumItemBytes else { throw ShelfEngine.Failure.oversized }
                return ShelfItem(kind: .file, name: url.lastPathComponent, data: try Data(contentsOf: url))
            }
        }
        if let link, WebRules.isWebScheme(link.scheme) {
            return [ShelfItem(kind: .link, name: "Clipboard.url", data: Data(link.absoluteString.utf8))]
        }
        return [ShelfItem(kind: .text, name: "Clipboard.txt", data: Data((text ?? "").utf8))]
    }
}
