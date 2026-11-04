import Foundation

extension MachRemoteModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "open-remote-mac-terminal", name: String(localized: "Open Remote Mac Terminal"),
        sfSymbol: "terminal", isEnabled: { NotchcastPreferences.shared.isOn(.machRemote) },
        run: { NotchcastCore.machRemote.openTerminal() })
}
