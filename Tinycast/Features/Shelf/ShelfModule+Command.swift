import AppKit

extension ShelfModule {
    nonisolated static let showCommand = NotchcastCommand(slug: "show-shelf", name: String(localized: "Show Shelf", table: "Notchcast"), sfSymbol: "tray", feature: .shelfBetweenMacs, run: { SettingsActionCommands.show(.notchcastTwoMacs, .shelfBetweenMacs) })
    nonisolated static let sendCommand = clipboardCommand {
        NSPasteboard.general.string(forType: .string)
    }

    nonisolated static func clipboardCommand(
        readText: @escaping @MainActor @Sendable () -> String?
    ) -> NotchcastCommand {
        NotchcastCommand(
        slug: "send-shelf-to-other-mac", name: String(localized: "Send Clipboard to Other Mac", table: "Notchcast"),
        sfSymbol: "paperplane", feature: .shelfBetweenMacs,
        isEnabled: {
            NotchcastPreferences.shared.isOn(.shelfBetweenMacs)
                && NotchcastPreferences.shared.isOn(.machLink)
        }, run: {
            NotchcastCore.shelf.sendClipboard(readText())
        })
    }

    func sendClipboard(_ text: String?) {
        guard let text, !text.isEmpty else {
            NotchcastCore.remoteResult(String(localized: "Clipboard is empty", table: "Notchcast"))
            return
        }
        let item = ShelfItem(kind: .text, name: "Clipboard.txt", data: Data(text.utf8))
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            do {
                try await send(item)
                guard !Task.isCancelled, isRunning, generation == token else { return }
                NotchcastCore.remoteResult(String(localized: "Sent Clipboard to Other Mac", table: "Notchcast"))
            } catch {
                guard !Task.isCancelled, isRunning, generation == token else { return }
                NotchcastCore.remoteResult(String(localized: "Could Not Send Clipboard to Other Mac", table: "Notchcast"))
            }
        }
    }
}
