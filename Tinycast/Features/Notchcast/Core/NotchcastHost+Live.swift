extension NotchcastHost {
    static func live(core: AppCore) -> Self {
        Self(
            showMessage: { [weak core] in core?.showMessage($0, tone: $1) },
            remoteResult: { NotchcastCore.remoteResult($0) },
            refreshNotchcastCommands: { [weak core] in core?.appIndex.refreshNotchcastCommands() },
            showLauncher: { [weak core] in core?.paletteCoordinator.showPalette(mode: .launcher) },
            dismissPalette: { [weak core] in
                guard let coordinator = core?.paletteCoordinator, coordinator.isVisible else { return }
                coordinator.hidePalette(restoreFocus: false)
            },
            showAppearanceSettings: { [weak core] in core?.settingsCoordinator.showSettings(tab: .general) },
            showSpotifySettings: { [weak core] in
                core?.settingsCoordinator.showSettings(tab: .notchcastMusicAndSound, revealing: .section(.notchcastSpotify))
            },
            showLinkSettings: { [weak core] in
                core?.settingsCoordinator.showSettings(tab: .notchcast, revealing: .section(.notchcastAIUsage))
            },
            appearanceEnabled: { [weak core] in core?.appearanceCoordinator.isEnabled == true },
            showThemes: { [weak core] in core?.appearanceCoordinator.showThemes() },
            choose: { [weak core] title, message, symbol, options, cancelTitle in
                let actions = options.map { DialogAction(title: $0) } + [DialogAction(title: cancelTitle, role: .cancel)]
                return await core?.choose(title: title, message: message, symbol: symbol,
                                          options: actions, defaultIndex: options.count) ?? options.count
            },
            finderSelection: { try await CopyPathSystemReader.read(.finderSelection) },
            browserAddresses: { try await CopyPathSystemReader.read(.browser(CopyPathTarget(processID: $0, bundleID: $1))) },
            confirm: { [weak core] in await core?.confirm(title: $0, message: $1, symbol: $2, confirmTitle: $3) ?? false }
        )
    }
}
