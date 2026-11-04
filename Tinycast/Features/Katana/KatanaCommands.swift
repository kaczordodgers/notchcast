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

    func runCommand(_ channel: KatanaChannel,
                    enabled: @escaping () -> Bool = { NotchcastPreferences.shared.isOn(.katana) },
                    confirm: @escaping @MainActor (KatanaChannel) async -> Bool = confirmChannel,
                    message: @escaping @MainActor (String, DialogTone) -> Void = {
                        AppCore.shared.showMessage($0, tone: $1)
                    }) {
        guard commandTask == nil, enabled() else { return }
        commandTask = Task { [weak self] in
            guard let self else { return }
            defer { self.commandTask = nil }
            guard await confirm(channel), !Task.isCancelled, enabled() else { return }
            do {
                try await self.client.selectChannel(channel)
                try Task.checkCancellation()
                message(String(localized: "Katana channel selected."), .success)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                message(error.localizedDescription, .danger)
            }
        }
    }

    private static func confirmChannel(_ channel: KatanaChannel) async -> Bool {
        await AppCore.shared.confirm(
            title: String(localized: "Change the Katana channel?"), message: channel.title,
            symbol: "guitars", confirmTitle: String(localized: "Change Channel"),
            tone: .neutral, confirmRole: .default)
    }
}
