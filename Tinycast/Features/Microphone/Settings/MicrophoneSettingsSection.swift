import SwiftUI

struct MicrophoneSettingsSection: View {
    @Environment(MicrophoneMute.self) private var microphone
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Section {
            NotchcastFeatureToggle(feature: .microphoneMute, anchor: .notchcastMicrophone)
            if let status = microphone.hotKeyStatus {
                Text(verbatim: "F5 (OSStatus \(status))")
                    .foregroundStyle(Theme.Colors.destructive)
            }
            NotchcastFeatureToggle(feature: .inUseMarks, anchor: .notchcastMicrophone)
            ForEach(Array(microphone.failures.enumerated()), id: \.offset) { _, failure in
                LabeledContent {
                    SymbolImage(name: "exclamationmark.circle.fill", size: Theme.Typography.menuSymbolSize)
                        .foregroundStyle(Theme.Colors.destructive)
                        .accessibilityHidden(true)
                } label: {
                    Text(failure.device)
                    Text(failure.message)
                }
                .accessibilityElement(children: .combine)
            }
        } header: { SettingsSectionHeader(.notchcastMicrophone) }
            .settingsEnabled(preferences.isOn(.island))
    }
}
