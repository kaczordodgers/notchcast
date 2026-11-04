extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        NotchcastDownloadLauncherCommands.video,
        NotchcastDownloadLauncherCommands.audio,
        NotchcastDownloadLauncherCommands.transcript,
        NotchcastDownloadLauncherCommands.webpage,
        NotchcastDownloadLauncherCommands.addDistill,
        NotchcastDownloadLauncherCommands.runDistill,
        NotchcastDownloadLauncherCommands.convert,
        NotchcastDownloadLauncherCommands.openDownloads,
        NotchcastDownloadLauncherCommands.openDistill,
    ]
}
