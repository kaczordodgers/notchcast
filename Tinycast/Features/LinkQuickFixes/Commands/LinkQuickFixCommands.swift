import AppKit

extension LinkQuickFixModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "fix-mac-link", name: String(localized: "Fix Mac Link", table: "Notchcast"),
        sfSymbol: "link", feature: .linkQuickFixes,
        isEnabled: { NotchcastPreferences.shared.isOn(.linkQuickFixes) },
        run: { Task { await NotchcastCore.linkQuickFixes.run() } })

    func configure() -> LinkQuickFixModule {
        state = {
            let reachability: Reachability
            switch NotchcastCore.linkHealth.health.reachability {
            case .up: reachability = .up
            case .down: reachability = .down
            case .unknown: reachability = .unknown
            }
            return (NotchcastCore.macLink.isRunning && NotchcastCore.macLink.isPaired, reachability)
        }
        message = { AppCore.shared.showMessage($0) }
        let executor = LinkQuickFixExecutor(copy: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString($0, forType: .string)
        }, open: { NSWorkspace.shared.open($0) }, settings: {
            AppCore.shared.settingsCoordinator.showSettings(tab: .notchcast, revealing: .section(.notchcastAIUsage))
        }, message: { AppCore.shared.showMessage($0) })
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
                return DialogAction(title: title)
            } + [DialogAction(title: String(localized: "Cancel"), role: .cancel)]
            let index = await AppCore.shared.choose(title: String(localized: "Fix Mac Link", table: "Notchcast"),
                message: note, symbol: "link", options: options, defaultIndex: actions.count)
            return actions.indices.contains(index) ? index : nil
        }
        return self
    }
}
