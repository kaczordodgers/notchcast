import SwiftUI

struct NotchcastSettingRow: View {
    let setting: NotchcastSetting

    var body: some View {
        switch NotchcastSettingsModule.module(of: setting) {
        case .island, .launcher, .musicAndSound, .dayAndTasks, .windowsAndDisplay:
            NotchcastSettingRowsA(setting: setting)
        case .monitorAndFans, .battery, .cleanAndUpdates, .tweaks, .privacyAndStartup:
            NotchcastSettingRowsB(setting: setting)
        case .downloads, .filesAndClipboard, .capture, .dictation:
            NotchcastSettingRowsC(setting: setting)
        case .aiAndAgents, .twoMacs, .backups:
            NotchcastSettingRowsD(setting: setting)
        }
    }
}
