import SwiftUI

struct NotchcastSettingRowsB: View {
    let setting: NotchcastSetting

    @ViewBuilder var body: some View {
        switch setting {
        case .monitorAndFansFanMode:
            NotchcastFanModeSettingRow()
        case .monitorAndFansAlertThresholds:
            NotchcastAlertCPUSettingRow()
            NotchcastAlertTemperatureSettingRow()
            NotchcastAlertMemorySettingRow()
            NotchcastAlertDiskSettingRow()
            NotchcastAlertBatterySettingRow()
        case .batteryChargeLimit:
            NotchcastChargePercentSettingRow()
        case .batteryAwakeDuration:
            NotchcastAwakeDurationSettingRow()
        case .batteryAccessoryReadings:
            NotchcastAccessoryReadingsSettingRow()
        case .updatesAppUpdates:
            NotchcastAppUpdatesSettingRow()
        case .updatesMacUpdate:
            NotchcastMacUpdateSettingRow()
        case .updatesCleaningMode:
            NotchcastCleaningModeSettingRow()
        case .tweaksTyping:
            NotchcastKeyRepeatSpeedSettingRow()
            NotchcastKeyRepeatDelaySettingRow()
            ForEach(TweakToggle.typing) { NotchcastTweaksPreferenceSettingRow(toggle: $0, module: TweaksModule.typing) }
        case .tweaksFinder:
            NotchcastNewFinderWindowsSettingRow()
            ForEach(TweakToggle.finder) { NotchcastTweaksPreferenceSettingRow(toggle: $0, module: TweaksModule.finder) }
        case .tweaksDock:
            ForEach(TweakToggle.dock) { NotchcastTweaksPreferenceSettingRow(toggle: $0, module: TweaksModule.dock) }
        case .privacyAndStartupLaunchAgents:
            NotchcastStartupItemsSettingRow()
        case .privacyAndStartupIPhoneBackup:
            NotchcastAutomaticBackupsSettingRow()
            NotchcastIPhoneBackupFolderSettingRow()
        default:
            EmptyView()
        }
    }
}
