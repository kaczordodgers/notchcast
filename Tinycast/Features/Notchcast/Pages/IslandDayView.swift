import SwiftUI

struct IslandDayView: View {
    @Environment(\.metrics) private var metrics
    @Environment(\.islandHeaderHeight) private var headerHeight
    let page: IslandDayPage
    var hasAccess: Bool? = nil

    var body: some View {
        if !(hasAccess ?? page.hasAccess) {
            VStack(spacing: metrics.spacing.md) {
                SymbolImage(name: "calendar", size: metrics.size.dialogIcon)
                    .accessibilityHidden(true)
                Text("Notchcast has no access to your calendar", tableName: "Notchcast")
                    .font(metrics.typography.rowTrailing)
                Button("Settings", action: page.showSettings)
                    .buttonStyle(.modalAction(.standard, fillsWidth: false))
                    .accessibilityLabel(String(localized: "Calendar Settings", table: "Notchcast"))
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(metrics.spacing.xxl)
        } else if page.events.isEmpty {
            VStack(spacing: metrics.spacing.md) {
                SymbolImage(name: "calendar", size: metrics.size.dialogIcon)
                    .accessibilityHidden(true)
                Text("Nothing scheduled today")
                    .font(metrics.typography.rowTrailing)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(metrics.spacing.xxl)
        } else {
            ScheduleList(results: page.events, selectedID: page.selection, now: page.clock.now,
                         scroll: page.scroll, onActivate: page.activate,
                         onActions: { _ in })
                .frame(height: listHeight)
        }
    }

    private var listHeight: CGFloat {
        let groups = MeetingDayGroup.grouping(page.events, now: page.clock.now, calendar: .current)
        let row = max(metrics.size.resultRowIcon, lineHeight(.body)) + metrics.spacing.sm * 2
        let header = lineHeight(.subheadline) + metrics.spacing.sectionHeaderBottom
        let firstInset = metrics.spacing.xs * 2 + metrics.spacing.md
        let laterInsets = CGFloat(max(0, groups.count - 1)) * metrics.spacing.sectionSpacing
        let height = CGFloat(page.events.count) * row + CGFloat(groups.count) * header
            + firstInset + laterInsets
        return min(NotchcastTheme.maximumHeight - headerHeight, height.rounded(.up))
    }

    private func lineHeight(_ style: NSFont.TextStyle) -> CGFloat {
        let font = NSFont.preferredFont(forTextStyle: style)
        return (font.ascender - font.descender + font.leading) * metrics.scale
    }
}

extension EnvironmentValues {
    @Entry var islandHeaderHeight = NotchcastTheme.monitorHeader
}
