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
        NotchcastToolsLauncherCommands.all[0],
        NotchcastToolsLauncherCommands.all[1],
        NotchcastToolsLauncherCommands.all[2],
        NotchcastToolsLauncherCommands.all[3],
        NotchcastToolsLauncherCommands.all[4],
        NotchcastToolsLauncherCommands.all[5],
        NotchcastToolsLauncherCommands.all[6],
        NotchcastToolsLauncherCommands.all[7],
    ]
}
