import Foundation

extension NotchcastFeature {
    @MainActor func setFromSettings(_ on: Bool) {
        switch self {
        case .cleanJunk, .cleanHistory, .cleanAIData, .cleanDisk, .cleanPurge, .cleanOptimize, .cleanSystem:
            NotchcastCore.clean.set(self, on)
        case .cleaningMode:
            NotchcastPreferences.shared.set(self, on)
            if !on { NotchcastCore.cleaning.stop() }
        case .appUpdates:
            NotchcastPreferences.shared.set(self, on)
            if !on { NotchcastCore.appUpdates.stop() }
        case .macUpdate:
            NotchcastPreferences.shared.set(self, on)
            if !on { NotchcastCore.macUpdate.stop() }
        case .typingTweaks:
            Task { await TweaksModule.typing.setFeature(self, enabled: on) }
        case .finderTweaks:
            Task { await TweaksModule.finder.setFeature(self, enabled: on) }
        case .dockTweaks:
            Task { await TweaksModule.dock.setFeature(self, enabled: on) }
        case .appleAppsTweaks:
            Task { await TweaksModule.appleApps.setFeature(self, enabled: on) }
        case .iPhoneBackupTweaks:
            Task { await TweaksModule.iPhoneBackup.setFeature(self, enabled: on) }
        case .spotlightOff:
            Task { await TweaksModule.shared.setSpotlight(enabled: on) }
        case _ where usesSystemToolsHelper:
            guard SystemToolsHelperPolicy.available(self) else { return }
            Task { await NotchcastCore.systemTools.set(self, enabled: on) }
        default:
            NotchcastPreferences.shared.set(self, on)
        }
    }

    @MainActor var settingsAvailable: Bool {
        switch self {
        case _ where NotchcastFeature.batteryChargingControl.contains(self):
            NotchcastPreferences.shared.isOn(self) || !BatteryModule.shared.chargingUnsupported
        case .fanControl, .monitorAlerts, .accessoryBatteries:
            NotchcastPreferences.shared.isOn(.systemMonitor)
        default:
            !helperLocked
        }
    }

    @MainActor var helperLocked: Bool {
        usesSystemToolsHelper && !SystemToolsHelperPolicy.available(self)
    }
}
