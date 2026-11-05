import SwiftUI

struct IslandHomeView: View {
    @Environment(\.metrics) private var metrics
    @Environment(IslandPagesCoordinator.self) private var pages

    var body: some View {
        if NotchcastPreferences.shared.isOn(.islandLiveActivities),
           !IslandActivityCenter.shared.activities.isEmpty {
            let activities = IslandActivityCenter.shared.activities
            let selection = pages.focusesHeader ? nil : pages.homeSelection
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(activities) { activity in
                            IslandActivityRow(activity: activity, selected: activity.id == selection)
                                .selectionFrame(activity.id == selection)
                                .id(activity.id.uuidString)
                        }
                    }
                    .padding(metrics.spacing.md)
                    .scrollOriginAnchor()
                }
                .edgeDissolve()
                .thinScrollbar()
                .scrollFollowsSelection(pages.homeScroll, row: selection?.uuidString,
                                        atOrigin: selection != nil && selection == activities.first?.id, proxy: proxy)
            }
            .frame(height: min(NotchcastTheme.maximumHeight - NotchcastTheme.monitorHeader,
                               CGFloat(activities.count) * NotchcastTheme.homeActivityRow))
        } else {
        VStack(spacing: metrics.spacing.md) {
            SymbolImage(name: "house", size: metrics.size.dialogIcon)
                .accessibilityHidden(true)
            Text("Nothing running right now", tableName: "Notchcast")
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
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            IslandActivityGlyph(activity: activity).frame(width: metrics.size.resultRowIcon)
            Text(activity.title).font(metrics.typography.rowTitle)
            Spacer()
            IslandActivityValue(activity: activity)
                .padding(.horizontal, metrics.spacing.md)
                .padding(.vertical, metrics.spacing.xxs)
                .background(Theme.Colors.controlSurface, in: RoundedRectangle(cornerRadius: Theme.Radius.keyCap))
            if let action = activity.action {
                IslandActionButton(title: action) { IslandActivityCenter.shared.perform(activity.id) }
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
