import SwiftUI

struct NotchcastToolsWiringSettingsRows: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        row(.cleaningMode, anchor: .notchcastCleaning) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                if NotchcastCore.cleaning.remaining > 0 {
                    Text(Duration.seconds(NotchcastCore.cleaning.remaining), format: .units())
                }
            }
            Button("Start") { NotchcastCore.cleaning.begin() }
        }
        if NotchcastCore.cleaning.needsGrant {
            Text("Accessibility permission is required to start cleaning mode.")
        }
        row(.appUpdates, anchor: .notchcastAppUpdates) {
            Button("Check") { NotchcastCore.appUpdates.check() }
                .settingsEnabled(!NotchcastCore.appUpdates.checking)
        }
        ForEach(NotchcastCore.appUpdates.results, id: \.app.id) { result in
            LabeledContent(result.app.id) {
                if let newer = result.isNewer {
                    Text(newer ? String(localized: "Update available") : String(localized: "Up to date"))
                    if let latest = result.latest { Text(latest) }
                } else { Text("Unknown") }
            }
        }
        row(.macUpdate, anchor: .notchcastMacUpdate) {
            Button("Run") { NotchcastCore.macUpdate.run(confirm: NotchcastCore.confirmMacUpdate) }
                .settingsEnabled(!NotchcastCore.macUpdate.running)
        }
        ForEach(MacUpdateStep.allCases, id: \.self) { step in
            if let event = NotchcastCore.macUpdate.progress.first(where: { $0.step == step }) {
                LabeledContent(step.title, value: event.state.title)
            }
        }
        if NotchcastCore.macUpdate.running {
            Button("Cancel") { NotchcastCore.macUpdate.cancel() }
        }
    }

    private func row(_ feature: NotchcastFeature, anchor: SettingsAnchor,
                     @ViewBuilder action: () -> some View) -> some View {
        LabeledContent {
            Toggle(feature.title, isOn: Binding(
                get: { preferences.isOn(feature) }, set: {
                    preferences.set(feature, $0)
                    if !$0 {
                        switch feature {
                        case .cleaningMode: NotchcastCore.cleaning.stop()
                        case .appUpdates: NotchcastCore.appUpdates.stop()
                        default: NotchcastCore.macUpdate.stop()
                        }
                    }
                }))
                .labelsHidden()
            action().settingsEnabled(preferences.isOn(feature))
        } label: {
            SettingsRowTitle(anchor, verbatim: feature.title)
            Text(feature.subtitle)
            if feature == .cleaningMode { Text("Media keys still work.") }
        }
    }
}

extension MacUpdateStep {
    var title: String {
        switch self {
        case .homebrewUpdate: String(localized: "Update Homebrew")
        case .homebrewUpgrade: String(localized: "Upgrade packages")
        case .commandLineTools: String(localized: "Update command-line tools")
        case .appStore: String(localized: "Upgrade App Store apps")
        }
    }
}

extension MacUpdateService.State {
    var title: String {
        switch self {
        case .running: String(localized: "Running")
        case .skipped: String(localized: "Skipped")
        case .done: String(localized: "Done")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        }
    }
}
