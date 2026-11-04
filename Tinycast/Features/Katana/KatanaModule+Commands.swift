import Foundation

extension KatanaModule {
    nonisolated static let panelCommand = command(.panel, title: String(localized: "Katana: Panel"))
    nonisolated static let a1Command = command(.a1, title: String(localized: "Katana: A1"))
    nonisolated static let a2Command = command(.a2, title: String(localized: "Katana: A2"))
    nonisolated static let b1Command = command(.b1, title: String(localized: "Katana: B1"))
    nonisolated static let b2Command = command(.b2, title: String(localized: "Katana: B2"))

    nonisolated private static func command(_ channel: KatanaChannel, title: String) -> NotchcastCommand {
        NotchcastCommand(
            slug: "katana-\(channel.title.lowercased())", name: title, sfSymbol: "guitars",
            feature: .katana, isEnabled: { NotchcastPreferences.shared.isOn(.katana) },
            run: {
                Task { @MainActor in
                    await NotchcastCore.katana.selectChannel(channel) { text, danger in
                        AppCore.shared.showMessage(text, tone: danger ? .danger : .neutral)
                    }
                }
            })
    }

    func selectChannel(_ channel: KatanaChannel, report: (String, Bool) -> Void) async {
        do {
            try await client.selectChannel(channel)
            let message: String
            switch channel {
            case .panel: message = String(localized: "Katana: Panel selected.")
            case .a1: message = String(localized: "Katana: A1 selected.")
            case .a2: message = String(localized: "Katana: A2 selected.")
            case .b1: message = String(localized: "Katana: B1 selected.")
            case .b2: message = String(localized: "Katana: B2 selected.")
            }
            report(message, false)
        } catch {
            report(error.localizedDescription, true)
        }
    }
}
