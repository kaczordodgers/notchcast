import AppKit

enum SettingsActionCommands {
    static let scanJunk = NotchcastCommand(
        slug: "settings-scanJunk", name: String(localized: "Scan Junk", table: "Notchcast"),
        sfSymbol: "magnifyingglass", feature: .cleanJunk,
        run: { scan(.cleanJunk) })

    static let loadHistory = NotchcastCommand(
        slug: "settings-loadHistory", name: String(localized: "Load Clean History", table: "Notchcast"),
        sfSymbol: "clock", feature: .cleanHistory,
        run: { scan(.cleanHistory) })

    static let scanAI = NotchcastCommand(
        slug: "settings-scanAI", name: String(localized: "Scan AI Data", table: "Notchcast"),
        sfSymbol: "magnifyingglass", feature: .cleanAIData,
        run: { scan(.cleanAIData) })

    static let scanDisk = NotchcastCommand(
        slug: "settings-scanDisk", name: String(localized: "Scan Disk", table: "Notchcast"),
        sfSymbol: "internaldrive", feature: .cleanDisk,
        run: { scan(.cleanDisk) })

    static let scanProjects = NotchcastCommand(
        slug: "settings-scanProjects", name: String(localized: "Scan Projects", table: "Notchcast"),
        sfSymbol: "folder", feature: .cleanPurge,
        run: { scan(.cleanPurge) })

    static let resetQuickLook = NotchcastCommand(
        slug: "settings-resetQuickLook", name: String(localized: "Reset Quick Look Cache", table: "Notchcast"),
        sfSymbol: "arrow.clockwise", feature: .cleanOptimize,
        run: { NotchcastCore.clean.coordinator.optimize(.quickLook) })

    static let clearDownloads = NotchcastCommand(
        slug: "settings-clearDownloads", name: String(localized: "Clear Download History", table: "Notchcast"),
        sfSymbol: "trash", feature: .cleanOptimize,
        run: { NotchcastCore.clean.coordinator.optimize(.downloadHistory) })

    static let rebuildOpenWith = NotchcastCommand(
        slug: "settings-rebuildOpenWith", name: String(localized: "Rebuild Open With Menu", table: "Notchcast"),
        sfSymbol: "arrow.clockwise", feature: .cleanOptimize,
        run: { NotchcastCore.clean.coordinator.optimize(.openWithMenu) })

    static let checkUpdates = NotchcastCommand(
        slug: "settings-checkUpdates", name: String(localized: "Check App Updates", table: "Notchcast"),
        sfSymbol: "arrow.triangle.2.circlepath", feature: .appUpdates,
        run: { show(.notchcastCleanAndUpdates, .appUpdates); NotchcastCore.appUpdates.check() })

    static let updateMac = NotchcastCommand(
        slug: "settings-updateMac", name: String(localized: "Update This Mac", table: "Notchcast"),
        sfSymbol: "arrow.triangle.2.circlepath", feature: .macUpdate,
        run: {
            show(.notchcastCleanAndUpdates, .macUpdate)
            NotchcastCore.macUpdate.run(confirm: NotchcastCore.confirmMacUpdate)
        })

    static let cancelUpdate = NotchcastCommand(
        slug: "settings-cancelUpdate", name: String(localized: "Cancel Mac Update", table: "Notchcast"),
        sfSymbol: "xmark", feature: .macUpdate,
        run: { NotchcastCore.macUpdate.cancel() })

    static let startCleaning = NotchcastCommand(
        slug: "settings-startCleaning", name: String(localized: "Start Cleaning Mode", table: "Notchcast"),
        sfSymbol: "keyboard", feature: .cleaningMode,
        run: { show(.notchcastCleanAndUpdates, .cleaningMode); NotchcastCore.cleaning.begin() })

    static let showLibrary = NotchcastCommand(
        slug: "settings-showLibrary", name: String(localized: "Show Library", table: "Notchcast"),
        sfSymbol: "folder", feature: .finderTweaks,
        run: { Task { await NotchcastCore.finderTweaks.showLibrary() } })

    static let restrictGaming = NotchcastCommand(
        slug: "settings-restrictGaming", name: String(localized: "Restrict Gaming", table: "Notchcast"),
        sfSymbol: "gamecontroller", feature: .appleAppsTweaks,
        run: { Task { await NotchcastCore.appleAppsTweaks.handOffProfile(.gameCenter) } })

    static let restrictMirroring = NotchcastCommand(
        slug: "settings-restrictMirroring", name: String(localized: "Restrict iPhone Mirroring", table: "Notchcast"),
        sfSymbol: "iphone", feature: .appleAppsTweaks,
        run: { Task { await NotchcastCore.appleAppsTweaks.handOffProfile(.iPhoneMirroring) } })

    static let restrictMusic = NotchcastCommand(
        slug: "settings-restrictMusic", name: String(localized: "Restrict Music Service", table: "Notchcast"),
        sfSymbol: "music.note", feature: .appleAppsTweaks,
        run: { Task { await NotchcastCore.appleAppsTweaks.handOffProfile(.musicService) } })

    static let restrictBooks = NotchcastCommand(
        slug: "settings-restrictBooks", name: String(localized: "Restrict Book Store", table: "Notchcast"),
        sfSymbol: "book", feature: .appleAppsTweaks,
        run: { Task { await NotchcastCore.appleAppsTweaks.handOffProfile(.bookstore) } })

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

    @MainActor static func scan(_ feature: NotchcastFeature) {
        show(.notchcastCleanAndUpdates, feature)
        CleanSettingsActions.scan(feature, coordinator: NotchcastCore.clean.coordinator)
    }
}
