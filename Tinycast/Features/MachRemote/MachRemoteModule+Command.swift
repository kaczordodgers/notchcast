import Foundation

extension MachRemoteModule {
    nonisolated static let sendFilesCommand = NotchcastCommand(
        slug: "send-to-remote-mac", name: String(localized: "Send to Remote Mac", table: "Notchcast"), sfSymbol: "paperplane", feature: .sendFiles,
        isEnabled: { NotchcastPreferences.shared.isOn(.machRemote) && NotchcastPreferences.shared.isOn(.sendFiles) },
        run: { NotchcastCore.machRemote.sendFinderSelection() })
    nonisolated static let updateCommand = NotchcastCommand(
        slug: "update-remote-mac", name: String(localized: "Update Remote Mac", table: "Notchcast"),
        sfSymbol: "arrow.clockwise", feature: .updateRemote,
        isEnabled: { NotchcastPreferences.shared.isOn(.machRemote) && NotchcastPreferences.shared.isOn(.updateRemote) },
        run: { NotchcastCore.machRemote.update() })
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "open-remote-mac-terminal", name: String(localized: "Open Remote Mac Terminal", table: "Notchcast"),
        sfSymbol: "terminal", feature: .machRemote, isEnabled: { NotchcastPreferences.shared.isOn(.machRemote) },
        run: { NotchcastCore.machRemote.openTerminal() })
}
