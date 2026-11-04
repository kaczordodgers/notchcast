import AppKit

extension KatanaModule {
    nonisolated static let panelCommand = command(.panel, name: String(localized: "Katana: Panel"))
    nonisolated static let a1Command = command(.a1, name: String(localized: "Katana: A1"))
    nonisolated static let a2Command = command(.a2, name: String(localized: "Katana: A2"))
    nonisolated static let b1Command = command(.b1, name: String(localized: "Katana: B1"))
    nonisolated static let b2Command = command(.b2, name: String(localized: "Katana: B2"))

    nonisolated private static func command(_ channel: KatanaChannel, name: String) -> NotchcastCommand {
        NotchcastCommand(slug: "katana-" + channel.title.lowercased(), name: name, sfSymbol: "guitars",
                         isEnabled: { NotchcastPreferences.shared.isOn(.katana) },
                         run: { NotchcastCore.katana.runCommand(channel) })
    }

    func runCommand(_ channel: KatanaChannel, enabled: () -> Bool = { NotchcastPreferences.shared.isOn(.katana) },
                    confirm: @MainActor (KatanaChannel) -> Bool = confirmChannel,
                    message: @escaping @MainActor (String) -> Void = { AppCore.shared.showMessage($0) }) {
        guard commandTask == nil, enabled() else { return }
        guard confirm(channel), enabled() else { return }
        commandTask = Task { [weak self] in
            guard let self else { return }
            defer { self.commandTask = nil }
            do {
                try await self.client.selectChannel(channel)
                try Task.checkCancellation()
                message(String(localized: "Katana channel selected."))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                message(error.localizedDescription)
            }
        }
    }

    private static func confirmChannel(_ channel: KatanaChannel) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Change the Katana channel?")
        alert.informativeText = channel.title
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.addButton(withTitle: String(localized: "Change Channel"))
        return alert.runModal() == .alertSecondButtonReturn
    }
}
