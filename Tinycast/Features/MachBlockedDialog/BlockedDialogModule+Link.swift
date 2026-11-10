import Foundation

extension BlockedDialogModule {
    /// Hub glue sets this before modules register, so the registration names no Mac Link type.
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
        }, enabled: {
            [.machLink, .island, .islandStatusMessages, .machBlockedDialogAlert]
                .allSatisfy { NotchcastPreferences.shared.isOn($0) }
        }, present: { owner in
            IslandActivityCenter.shared.showMessage(
                String(localized: "Other Mac: \(owner) is waiting.", table: "Notchcast"), tone: .neutral, dwell: 8,
                id: "machBlockedDialog.\(owner)")
        })
    }
}
