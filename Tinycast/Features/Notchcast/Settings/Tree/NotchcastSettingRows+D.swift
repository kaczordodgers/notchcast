import SwiftUI

struct NotchcastSettingRowsD: View {
    let setting: NotchcastSetting

    @ViewBuilder var body: some View {
        switch setting {
        case .aiAndAgentsUsageGateway:
            AIUsageGatewaySettingRow()
        case .aiAndAgentsBuildSnapshot:
            BuildStatsSnapshotSettingRow()
        case .aiAndAgentsCLIInstall:
            AgentCLIInstallSettingRow(module: NotchcastCore.agentCLI)
        case .aiAndAgentsChatTools:
            if let module = NotchcastCore.agentChatTools {
                AgentChatToolsAccessSettingRow(module: module)
            }
        case .aiAndAgentsVoiceDestination:
            if let module = NotchcastCore.voiceAsk {
                VoiceAskDestinationSettingRow(module: module)
            }
        case .twoMacsConnection:
            MacLinkStatusSettingRow(link: NotchcastCore.macLink)
            MacLinkPairingSettingRow(link: NotchcastCore.macLink)
        case .twoMacsRemotePaths:
            RemoteMacAddressSettingRow()
            RemoteTerminalDirectorySettingRow()
            RemoteUpdateScriptSettingRow()
        case .backupsStatusPath:
            BackupStatusPathSettingRow()
        default:
            EmptyView()
        }
    }
}
