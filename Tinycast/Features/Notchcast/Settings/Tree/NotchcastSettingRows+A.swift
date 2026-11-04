import SwiftUI

struct NotchcastSettingRowsA: View {
    let setting: NotchcastSetting

    @ViewBuilder var body: some View {
        switch setting {
        case .islandHoverDelay:
            IslandHoverDelaySettingRow()
        case .launcherGitHubToken:
            GitHubTokenSettingRow()
        case .launcherAppearance:
            AppearanceSurfaceSettingRow()
            AppearanceLightThemeSettingRow()
            AppearanceDarkThemeSettingRow()
            AppearanceOpacitySettingRow()
            AppearanceImportSettingRow()
        case .musicAndSoundSpotifyConnect:
            SpotifyStatusSettingRow()
            SpotifyAPIKeySettingRow()
            SpotifyDeviceNameSettingRow()
            SpotifyBuildSettingRow()
            SpotifyTermsSettingRow()
        case .musicAndSoundAudioPriority:
            AudioPriorityOutputsSettingRow()
            AudioPriorityMicrophonesSettingRow()
            AudioPriorityFailureSettingRow()
        case .musicAndSoundInUseFailures:
            MicrophoneDeviceFailuresSettingRow()
        case .dayAndTasksWeatherCity:
            WeatherCitySettingRow(store: NotchcastCore.weather.store)
        case .dayAndTasksMarketSymbols:
            MarketSymbolsSettingRow(markets: NotchcastCore.markets.store)
        case .dayAndTasksTaskImport:
            TaskCountSettingRow()
            TodoistImportSettingRow()
        case .dayAndTasksTimerOptions:
            TimerSoundSettingRow(store: NotchcastCore.timers.store)
            TimerDefaultDurationSettingRow(store: NotchcastCore.timers.store)
        case .windowsAndDisplayExcludedApps:
            ExcludedBundleIDsSettingRow()
        case .windowsAndDisplayQuitProtection:
            QuitProtectionModeSettingRow(store: NotchcastCore.quitProtection)
            QuitProtectionCloseSettingRow(store: NotchcastCore.quitProtection)
            QuitProtectionExceptionsSettingRow(store: NotchcastCore.quitProtection)
            QuitProtectionAddAppSettingRow(store: NotchcastCore.quitProtection)
        case .windowsAndDisplayBrightness:
            DisplayBrightnessSettingRow(controller: NotchcastCore.brightness.controller)
        default:
            EmptyView()
        }
    }
}
