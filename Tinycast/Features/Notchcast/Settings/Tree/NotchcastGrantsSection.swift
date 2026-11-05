import SwiftUI

struct NotchcastGrantsSection: View {
    let grants: [NotchcastGrant]
    let anchor: SettingsAnchor
    @Environment(SettingsNavigationState.self) private var navigation

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ForEach(grants, id: \.self) { grant in
                    let granted = NotchcastCore.grantStatuses.values[grant] ?? false
                    LabeledContent {
                        HStack(spacing: Theme.Spacing.lg) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .accessibilityHidden(true)
                                Text(granted ? "Granted" : "Not granted")
                            }
                            .foregroundStyle(granted ? .green : .orange)
                            Button("Open…") {
                                grant.open(navigation)
                            }
                        }
                    } label: {
                        Text(grant.title)
                    }
                }
                .task(id: context.date) {
                    await NotchcastCore.grantStatuses.refresh(grants)
                }
            }
        } header: {
            SettingsSectionHeader(anchor)
        }
    }
}
