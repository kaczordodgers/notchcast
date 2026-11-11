import Foundation

extension BlockedDialogModule {
    /// Set by hub glue in `start` before registrants register; `register` returns [] while nil.
    static var linkChannel: MachLinkChannel?

    static func linked(to channel: MachLinkChannel) -> BlockedDialogModule {
        channel.manager.register("dialogs") { request in
            guard NotchcastPreferences.shared.isOn(.machBlockedDialogAlert) else {
                throw MachLinkMessage.Failure.disconnected
            }
            return try MachLinkMessage(id: request.id, method: request.method, value: BlockedDialogWindows.current())
        }
        return BlockedDialogModule(transport: { request in
            let windows = try await channel.request(true, method: request.method, timeout: .seconds(2),
                as: [BlockedDialogWindow].self)
            return try MachLinkMessage(id: request.id, method: request.method, value: windows)
        }, enabled: { NotchcastPreferences.shared.isEnabled(.machBlockedDialogAlert) }, present: { owner in
            IslandActivityCenter.shared.showMessage(
                String(localized: "Other Mac: \(owner) is waiting.", table: "Notchcast"), tone: .neutral, dwell: 8,
                id: "machBlockedDialog.\(owner)")
        })
    }
}
