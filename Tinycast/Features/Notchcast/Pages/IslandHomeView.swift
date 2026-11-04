import SwiftUI

struct IslandHomeView: View {
    @Environment(\.metrics) private var metrics
    var body: some View {
        if NotchcastPreferences.shared.isOn(.islandLiveActivities),
           !IslandActivityCenter.shared.activities.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(IslandActivityCenter.shared.activities) { activity in
                        IslandActivityRow(activity: activity)
                    }
                }
                .padding(metrics.spacing.md)
            }
            .edgeDissolve()
            .thinScrollbar()
            .frame(height: min(NotchcastTheme.maximumHeight - NotchcastTheme.monitorHeader,
                               CGFloat(IslandActivityCenter.shared.activities.count) * NotchcastTheme.homeActivityRow))
        } else {
        VStack(spacing: metrics.spacing.md) {
            SymbolImage(name: "house", size: metrics.size.dialogIcon)
                .accessibilityHidden(true)
            Text("Nothing running right now")
                .font(metrics.typography.rowTrailing)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(metrics.spacing.xxl)
        }
    }
}

private struct IslandActivityRow: View {
    @Environment(\.metrics) private var metrics
    let activity: IslandActivity
    @State private var hovered = false

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            IslandActivityGlyph(activity: activity).frame(width: metrics.size.resultRowIcon)
            Text(activity.title).font(metrics.typography.rowTitle)
            Spacer()
            IslandActivityValue(activity: activity)
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.xxs)
                .background(Theme.Colors.controlSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.keyCap))
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(hovered ? Theme.Colors.rowHover : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.row))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
    }
}
