import AppKit

enum SettingsActionCommands {
    static let checkUpdates = NotchcastCommand(
        slug: "settings-checkUpdates", name: String(localized: "Check App Updates", table: "Notchcast"),
        sfSymbol: "arrow.triangle.2.circlepath", feature: .appUpdates,
        run: { show(.notchcastUpdates, .appUpdates); NotchcastCore.appUpdates.check() })

    static let updateMac = NotchcastCommand(
        slug: "settings-updateMac", name: String(localized: "Update This Mac", table: "Notchcast"),
        sfSymbol: "arrow.triangle.2.circlepath", feature: .macUpdate,
        run: {
            show(.notchcastUpdates, .macUpdate)
            NotchcastCore.macUpdate.run(confirm: NotchcastCore.confirmMacUpdate)
        })

    static let cancelUpdate = NotchcastCommand(
        slug: "settings-cancelUpdate", name: String(localized: "Cancel Mac Update", table: "Notchcast"),
        sfSymbol: "xmark", feature: .macUpdate,
        run: { NotchcastCore.macUpdate.cancel() })

    static let startCleaning = NotchcastCommand(
        slug: "settings-startCleaning", name: String(localized: "Start Cleaning Mode", table: "Notchcast"),
        sfSymbol: "keyboard", feature: .cleaningMode,
        run: { show(.notchcastUpdates, .cleaningMode); NotchcastCore.cleaning.begin() })

    static let showLibrary = NotchcastCommand(
        slug: "settings-showLibrary", name: String(localized: "Show Library", table: "Notchcast"),
        sfSymbol: "folder", feature: .finderTweaks,
        run: { Task { await TweaksModule.finder.showLibrary() } })

    static let restrictGaming = NotchcastCommand(
        slug: "settings-restrictGaming", name: String(localized: "Restrict Gaming", table: "Notchcast"),
        sfSymbol: "gamecontroller", feature: .appleAppsTweaks,
        run: { Task { await TweaksModule.appleApps.handOffProfile(.gameCenter) } })

    static let restrictMirroring = NotchcastCommand(
        slug: "settings-restrictMirroring", name: String(localized: "Restrict iPhone Mirroring", table: "Notchcast"),
        sfSymbol: "iphone", feature: .appleAppsTweaks,
        run: { Task { await TweaksModule.appleApps.handOffProfile(.iPhoneMirroring) } })

    static let restrictMusic = NotchcastCommand(
        slug: "settings-restrictMusic", name: String(localized: "Restrict Music Service", table: "Notchcast"),
        sfSymbol: "music.note", feature: .appleAppsTweaks,
        run: { Task { await TweaksModule.appleApps.handOffProfile(.musicService) } })

    static let restrictBooks = NotchcastCommand(
        slug: "settings-restrictBooks", name: String(localized: "Restrict Book Store", table: "Notchcast"),
        sfSymbol: "book", feature: .appleAppsTweaks,
        run: { Task { await TweaksModule.appleApps.handOffProfile(.bookstore) } })

    static let installCLI = NotchcastCommand(
        slug: "settings-installCLI", name: String(localized: "Install Command Line Tool", table: "Notchcast"),
        sfSymbol: "terminal", feature: .agentCLI,
        run: { show(.notchcastAIAndAgents, .agentCLI); NotchcastCore.agentCLI.installer.install() })

    static let revealBackup = NotchcastCommand(
        slug: "settings-revealBackup", name: String(localized: "Reveal iPhone Backup Folder", table: "Notchcast"),
        sfSymbol: "folder", feature: .iPhoneBackupTweaks,
        run: {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath:
                IPhoneBackupPolicy.backupDirectory(home: FileManager.default.homeDirectoryForCurrentUser).path)
        })

    @MainActor static func show(_ tab: SettingsTab, _ feature: NotchcastFeature) {
        AppCore.shared.settingsCoordinator.showSettings(
            tab: tab, revealing: .section(.notchcast(feature: feature)))
    }

}
