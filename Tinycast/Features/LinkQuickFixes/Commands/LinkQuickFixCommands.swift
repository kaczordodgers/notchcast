import AppKit

extension LinkQuickFixModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "fix-mac-link", name: String(localized: "Fix Mac Link", table: "Notchcast"),
        sfSymbol: "link", feature: .linkQuickFixes,
        isEnabled: { NotchcastPreferences.shared.isOn(.linkQuickFixes) },
        run: { Task { await LinkQuickFixModule.shared.run() } })

    func configure() -> LinkQuickFixModule {
        message = { NotchcastHost.current.showMessage($0, .success) }
        let executor = LinkQuickFixExecutor(copy: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString($0, forType: .string)
        }, open: { NSWorkspace.shared.open($0) }, settings: {
            NotchcastHost.current.showLinkSettings()
        }, message: { NotchcastHost.current.showMessage($0, .success) })
        execute = executor.run
        choose = { actions, note in
            let options = actions.map { action in
                let title: String
                switch action {
                case .openNetworkSettings: title = String(localized: "Open Network Settings", table: "Notchcast")
                case .relinkInConnections: title = String(localized: "Open Mac Link Settings", table: "Notchcast")
                case .copyCommand(_, .dnsFailure): title = String(localized: "Copy DNS Reset Command", table: "Notchcast")
                case .copyCommand(_, .tailscaleStopped): title = String(localized: "Copy Tailscale Command", table: "Notchcast")
                case .copyCommand: title = String(localized: "Copy Sync Command", table: "Notchcast")
                case .openMirrorLog: title = String(localized: "Open Log", table: "Notchcast")
                }
                return title
            }
            let index = await NotchcastHost.current.choose(String(localized: "Fix Mac Link", table: "Notchcast"),
                note, "link", options, String(localized: "Cancel"))
            return actions.indices.contains(index) ? index : nil
        }
        return self
    }
}
