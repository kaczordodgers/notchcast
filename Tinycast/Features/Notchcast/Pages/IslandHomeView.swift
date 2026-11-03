import SwiftUI

struct IslandHomeView: View {
    var body: some View {
        if NotchcastPreferences.shared.isOn(.islandLiveActivities),
           !IslandActivityCenter.shared.activities.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(IslandActivityCenter.shared.activities) { activity in
                        IslandActivityRow(activity: activity)
                    }
                }
                .padding(Theme.Spacing.md)
            }
            .edgeDissolve()
            .thinScrollbar()
            .frame(height: min(NotchcastTheme.maximumHeight - NotchcastTheme.monitorHeader,
                               CGFloat(IslandActivityCenter.shared.activities.count) * 56))
        } else {
        VStack(spacing: Theme.Spacing.md) {
            SymbolImage(name: "house", size: Theme.Size.dialogIcon)
                .accessibilityHidden(true)
            Text("Nothing running right now")
                .font(Theme.Typography.rowTrailing)
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.xxl)
        }
    }
}

private struct IslandActivityRow: View {
    let activity: IslandActivity
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            IslandActivityGlyph(activity: activity).frame(width: Theme.Size.resultRowIcon)
            Text(activity.title).font(Theme.Typography.rowTitle)
            Spacer()
            IslandActivityValue(activity: activity)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(Theme.Colors.controlSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.keyCap))
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(hovered ? Theme.Colors.rowHover : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.row))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
    }
}
