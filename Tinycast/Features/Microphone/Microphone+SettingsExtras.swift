import SwiftUI

extension NotchcastFeatureSettingsExtras {
    static var microphoneMute: Self { Self(needsServices: true, rows: AnyView(MicrophoneHotKeyFailureSettingRow())) }
    static var inUseMarks: Self { Self(needsServices: true) }
}
