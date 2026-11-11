import SwiftUI

extension NotchcastFeatureSettingsExtras {
    static func battery(_ feature: NotchcastFeature) -> Self {
        Self(rows: AnyView(NotchcastBatteryStatusSettingRow(feature: feature)))
    }
}
