extension NotchcastCommandCatalog {
    static let all: [NotchcastCommand] = [
        IslandController.launcherCommand,
        IslandPage.home.launcherCommand,
        IslandPage.day.launcherCommand,
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
