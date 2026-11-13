import SwiftUI
import AppKit

struct NotchcastCleaningModeSettingRow: View {

    var body: some View {
        if NotchcastCore.cleaning.needsGrant {
            Text("Accessibility permission is required to start cleaning mode.", tableName: "Notchcast")
        }
    }
}

struct NotchcastAppUpdatesSettingRow: View {

    var body: some View {
        ForEach(NotchcastCore.appUpdates.results, id: \.app.id) { result in
            LabeledContent(result.app.id) {
                if let newer = result.isNewer {
                    Text(newer ? String(localized: "Update available", table: "Notchcast") : String(localized: "Up to date", table: "Notchcast"))
                    if let latest = result.latest { Text(latest) }
                } else {
                    Text("Unknown", tableName: "Notchcast")
                }
                if let link = result.settingsLink { Link(destination: link) { Text("Open") } }
            }
        }

    }
}

struct NotchcastMacUpdateSettingRow: View {

    var body: some View {
        ForEach(MacUpdateStep.allCases, id: \.self) { step in
            if let event = NotchcastCore.macUpdate.progress.first(where: { $0.step == step }) {
                LabeledContent(step.title) {
                    Text(event.state.title)
                    if let reason = event.state.reason { Text(reason).textSelection(.enabled) }
                }
            }
        }

    }
}
