import SwiftUI

extension NotchcastFeatureSettingsExtras {
    static func battery(_ feature: NotchcastFeature) -> Self {
        Self(rows: AnyView(Group {
            NotchcastBatteryStatusSettingRow(feature: feature)
            if feature == .batteryCalibration {
                if let guidance = BatteryModule.shared.calibrationGuidance {
                    Text(guidance).foregroundStyle(.secondary)
                }
                Text("After relaunch, start calibration again from step 1.", tableName: "Notchcast")
                    .foregroundStyle(.secondary)
            }
        }))
    }
}
