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
        case .cleanAndUpdatesAppUpdates:
            NotchcastAppUpdatesSettingRow()
        case .cleanAndUpdatesMacUpdate:
            NotchcastMacUpdateSettingRow()
        case .cleanAndUpdatesCleaningMode:
            NotchcastCleaningModeSettingRow()
        case .tweaksTyping:
            NotchcastKeyRepeatSpeedSettingRow()
            NotchcastKeyRepeatDelaySettingRow()
            NotchcastAutocorrectSettingRow()
            NotchcastSmartPunctuationSettingRow()
            NotchcastDoubleSpacePeriodSettingRow()
            NotchcastAutoCapitalizeSettingRow()
            NotchcastKeyRepeatSettingRow()
        case .tweaksFinder:
            NotchcastShowLibrarySettingRow()
            NotchcastNewFinderWindowsSettingRow()
            NotchcastFileExtensionsSettingRow()
            NotchcastHiddenFilesSettingRow()
            NotchcastPathBarSettingRow()
            NotchcastStatusBarSettingRow()
            NotchcastFoldersFirstSettingRow()
            NotchcastSearchThisFolderSettingRow()
            NotchcastExtensionWarningSettingRow()
            NotchcastPathInTitleSettingRow()
            NotchcastNetworkDsStoreSettingRow()
            NotchcastTrash30DaysSettingRow()
            NotchcastSaveLocallySettingRow()
            NotchcastExpandedSaveSettingRow()
            NotchcastListViewSettingRow()
            NotchcastUsbDsStoreSettingRow()
            NotchcastDesktopDisksSettingRow()
        case .tweaksDock:
            NotchcastDockRecentsSettingRow()
            NotchcastDockDelaySettingRow()
            NotchcastDockBounceSettingRow()
            NotchcastMinimizeToAppSettingRow()
            NotchcastWindowAnimationsSettingRow()
            NotchcastTileMarginsSettingRow()
            NotchcastScreenshotShadowSettingRow()
            NotchcastClickToDesktopSettingRow()
            NotchcastDesktopWidgetsSettingRow()
        case .privacyAndStartupLaunchAgents:
            NotchcastStartupItemsSettingRow()
        case .privacyAndStartupAppleApps:
            NotchcastGameCenterSettingRow()
            NotchcastIPhoneMirroringSettingRow()
            NotchcastMusicServiceSettingRow()
            NotchcastBookstoreSettingRow()
        case .privacyAndStartupIPhoneBackup:
            NotchcastAutomaticBackupsSettingRow()
            NotchcastIPhoneBackupFolderSettingRow()
        case .cleanAndUpdatesJunk:
            NotchcastCleanActionsSettingRow(feature: .cleanJunk)
        case .cleanAndUpdatesHistory:
            NotchcastCleanActionsSettingRow(feature: .cleanHistory)
        case .cleanAndUpdatesAIData:
            NotchcastCleanActionsSettingRow(feature: .cleanAIData)
        case .cleanAndUpdatesDisk:
            NotchcastCleanActionsSettingRow(feature: .cleanDisk)
        case .cleanAndUpdatesPurge:
            NotchcastCleanActionsSettingRow(feature: .cleanPurge)
        case .cleanAndUpdatesOptimize:
            NotchcastCleanActionsSettingRow(feature: .cleanOptimize)
        case .cleanAndUpdatesSystem:
            NotchcastCleanActionsSettingRow(feature: .cleanSystem)
        default:
            EmptyView()
        }
    }
}
