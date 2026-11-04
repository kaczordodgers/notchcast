import SwiftUI

struct IslandHeaderView: View {
    @Environment(IslandController.self) private var island
    @Environment(IslandPagesCoordinator.self) private var pages
    let cameraWidth: CGFloat
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.xxs) {
                ForEach(pages.pages) { page in
                    BarButton(chrome: .rounded, isSelected: island.page == page.id) {
                        island.selectPage(page.id)
                    } label: {
                        Text(page.title)
                            .font(Theme.Typography.bar)
                            .foregroundStyle(island.page == page.id
                                             ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    }
                    .overlay { focusOutline(pages.pages.firstIndex(of: page)) }
                    .tooltip(keyCaps: ["⌘", page.key])
                    .accessibilityLabel(Text(page.title))
                    .accessibilityAddTraits(island.page == page.id ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            Color.clear.frame(width: cameraWidth).accessibilityHidden(true)
            HStack(spacing: Theme.Spacing.xxs) {
                Spacer(minLength: 0)
                if NotchcastPreferences.shared.isOn(.islandStatusMessages),
                   let message = IslandActivityCenter.shared.message {
                    IslandStatusView(message: message)
                }
                if pages.isRefreshing {
                    SymbolImage(name: "progress.indicator", size: NotchcastTheme.headerGlyph)
                        .symbolEffect(.variableColor.iterative)
                        .foregroundStyle(Theme.Colors.progress)
                        .accessibilityLabel(String(localized: "Refreshing", table: "Notchcast"))
                }
                BarButton(chrome: .rounded, isSelected: island.isPinned, isCompact: true) {
                    island.togglePin()
                } label: {
                    SymbolImage(name: island.isPinned ? "pin.fill" : "pin", size: NotchcastTheme.headerGlyph)
                }
                .overlay { focusOutline(pages.pages.count) }
                .tooltip(keyCaps: ["⌘", "P"])
                .accessibilityLabel(island.isPinned
                                    ? String(localized: "Unpin Island", table: "Notchcast") : String(localized: "Pin Island", table: "Notchcast"))
                .accessibilityAddTraits(island.isPinned ? .isSelected : [])
                BarButton(chrome: .rounded, isCompact: true, action: pages.showSettings) {
                    SymbolImage(name: "gearshape", size: NotchcastTheme.headerGlyph)
                }
                .overlay { focusOutline(pages.pages.count + 1) }
                .tooltip(String(localized: "Notchcast Settings", table: "Notchcast"), edge: .bottom)
                .accessibilityLabel(String(localized: "Notchcast Settings", table: "Notchcast"))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: height)
    }

    @ViewBuilder private func focusOutline(_ index: Int?) -> some View {
        if island.hasKeyboardFocus, let index, pages.headerFocus == index {
            RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
