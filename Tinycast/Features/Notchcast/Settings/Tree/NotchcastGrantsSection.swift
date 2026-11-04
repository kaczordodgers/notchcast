import SwiftUI

struct NotchcastGrantsSection: View {
    let grants: [NotchcastGrant]
    let anchor: SettingsAnchor
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        Section {
            // Re-read each second, as upstream's Permissions page does, so a grant shows up live.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                ForEach(grants, id: \.self) { grant in
                    LabeledContent {
                        HStack(spacing: Theme.Spacing.lg) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: grant.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .accessibilityHidden(true)
                                Text(grant.isGranted ? "Granted" : "Not granted")
                            }
                            .foregroundStyle(grant.isGranted ? .green : .orange)
                            Button("Open…") {
                                grant.open(navigation)
                            }
                        }
                    } label: {
                        Text(grant.title)
                    }
                }
            }
        } header: {
            SettingsSectionHeader(anchor)
        }
    }
}
