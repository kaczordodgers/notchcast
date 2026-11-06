import SwiftUI

struct IslandHomeView: View {
    @Environment(\.metrics) private var metrics
    var body: some View {
        if NotchcastPreferences.shared.isOn(.islandLiveActivities),
           !IslandActivityCenter.shared.activities.isEmpty {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(IslandActivityCenter.shared.ranked) { activity in
                        IslandActivityRow(activity: activity,
                                          selected: activity.id == IslandActivityCenter.shared.ranked.first?.id)
                    }
                }
                .padding(metrics.spacing.md)
            }
            .edgeDissolve()
            .thinScrollbar()
            .frame(height: min(NotchcastTheme.maximumHeight - NotchcastTheme.monitorHeader,
                               CGFloat(IslandActivityCenter.shared.activities.count)
                               * (metrics.size.resultRowIcon + metrics.spacing.sm * 2) + metrics.spacing.md * 2))
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

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            IslandGlyph(symbol: activity.symbol ?? (activity.kind == .status ? "info.circle" : activity.shownSymbol),
                        tone: activity.tone)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(activity.title).font(metrics.typography.rowTitle).lineLimit(1)
            Spacer()
            if IslandItemParts.hasValue(activity) {
                IslandActivityValue(activity: activity)
            }
        }
        .frame(height: metrics.size.resultRowIcon)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear,
                    in: RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
