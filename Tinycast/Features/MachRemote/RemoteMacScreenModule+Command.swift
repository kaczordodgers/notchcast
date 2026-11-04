import AppKit

extension RemoteMacScreenModule {
    static func live() -> RemoteMacScreenModule {
        RemoteMacScreenModule(preferences: .shared, open: { NSWorkspace.shared.open($0) },
            post: NotchcastCore.remoteNotice, changed: { AppCore.shared.appIndex.refreshNotchcastCommands() })
    }

    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "open-remote-mac-screen", name: String(localized: "Open Remote Mac Screen"),
        sfSymbol: "display", isEnabled: { NotchcastPreferences.shared.isOn(.remoteMacScreen) },
        run: { NotchcastCore.remoteMacScreen.openScreen() })
}
