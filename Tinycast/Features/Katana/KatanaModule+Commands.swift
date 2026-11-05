import Foundation

extension KatanaModule {
    nonisolated static let panelCommand = command(.panel, title: String(localized: "Select Katana Panel", table: "Notchcast"))
    nonisolated static let a1Command = command(.a1, title: String(localized: "Select Katana A1", table: "Notchcast"))
    nonisolated static let a2Command = command(.a2, title: String(localized: "Select Katana A2", table: "Notchcast"))
    nonisolated static let b1Command = command(.b1, title: String(localized: "Select Katana B1", table: "Notchcast"))
    nonisolated static let b2Command = command(.b2, title: String(localized: "Select Katana B2", table: "Notchcast"))

    nonisolated private static func command(_ channel: KatanaChannel, title: String) -> NotchcastCommand {
        NotchcastCommand(
            slug: "katana-\(channel.title.lowercased())", name: title, sfSymbol: "guitars",
            feature: .katana, isEnabled: { NotchcastPreferences.shared.isOn(.katana) },
            run: {
                Task { @MainActor in
                    await NotchcastCore.katana.selectChannel(channel) { text, danger in
                        if danger {
                            AppCore.shared.showMessage(text, tone: .danger)
                        } else {
                            AppCore.shared.showMessage(text)
                        }
                    }
                }
            })
    }

    func selectChannel(_ channel: KatanaChannel, report: (String, Bool) -> Void) async {
        do {
            try await client.selectChannel(channel)
            guard !Task.isCancelled, NotchcastPreferences.shared.isOn(.katana) else { return }
            let message: String
            switch channel {
            case .panel: message = String(localized: "Katana Panel Selected", table: "Notchcast")
            case .a1: message = String(localized: "Katana A1 Selected", table: "Notchcast")
            case .a2: message = String(localized: "Katana A2 Selected", table: "Notchcast")
            case .b1: message = String(localized: "Katana B1 Selected", table: "Notchcast")
            case .b2: message = String(localized: "Katana B2 Selected", table: "Notchcast")
            }
            report(message, false)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, NotchcastPreferences.shared.isOn(.katana) else { return }
            report(error.localizedDescription, true)
        }
    }
}
