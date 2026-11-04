import AppKit

extension LinkQuickFixModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "fix-mac-link", name: String(localized: "Fix Mac Link"), sfSymbol: "link",
        feature: .linkQuickFixes,
        isEnabled: { NotchcastPreferences.shared.isOn(.linkQuickFixes) },
        run: { Task { await NotchcastCore.linkQuickFixes.run() } })

    func configure() -> LinkQuickFixModule {
        state = { (NotchcastCore.macLink.isPaired, NotchcastCore.linkHealth.health.reachability == .down) }
        message = { AppCore.shared.showMessage($0) }
        let executor = LinkQuickFixExecutor(copy: {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString($0, forType: .string)
        }, open: { NSWorkspace.shared.open($0) }, settings: {
            AppCore.shared.settingsCoordinator.showSettings(tab: .notchcast, revealing: .notchcastSystem)
        }, message: { AppCore.shared.showMessage($0) })
        execute = executor.run
        choose = { actions in
            let options = actions.map { action in
                let title: String
                switch action {
                case .openNetworkSettings: title = String(localized: "Open Network Settings")
                case .relinkInConnections: title = String(localized: "Mac Link")
                case let .copyCommand(command): title = command
                case .openMirrorLog: title = String(localized: "Open Log")
                }
                return DialogAction(title: title)
            } + [DialogAction(title: String(localized: "Cancel"), role: .cancel)]
            let index = await AppCore.shared.choose(title: String(localized: "Fix Mac Link"),
                message: nil, symbol: "link", options: options, defaultIndex: actions.count)
            return actions.indices.contains(index) ? index : nil
        }
        return self
    }
}
