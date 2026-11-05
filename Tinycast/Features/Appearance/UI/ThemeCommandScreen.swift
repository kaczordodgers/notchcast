import SwiftUI

struct ThemeCommandScreen: PaletteScreen {
    let coordinator: AppearanceCoordinator
    let vm: PaletteState

    var rows: [AppearanceThemeCommand.Row] {
        guard coordinator.isEnabled else { return [] }
        return AppearanceThemeCommand.rows(
            currentAppearance: NSApp.effectiveAppearance.isDark ? .dark : .light,
            light: coordinator.store.light, dark: coordinator.store.dark,
            imported: coordinator.store.imported, query: vm.query)
    }

    var primaryActionTitle: String { String(localized: "Use Theme", table: "Notchcast") }
    var landingSelection: Int { rows.firstIndex(where: \.isSelected) ?? 0 }

    func hasActions(at selection: Int) -> Bool { false }

    func activate(at selection: Int) {
        guard rows.indices.contains(selection) else { return }
        coordinator.apply(rows[selection].target)
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            ThemeCommandList(rows: rows, selection: selection, scroll: scroll, vm: vm)
                .environment(coordinator))
    }
}

private struct ThemeCommandList: View {
    let rows: [AppearanceThemeCommand.Row]
    let selection: Int
    let scroll: ScrollIntent
    let vm: PaletteState
    @Environment(AppearanceCoordinator.self) private var coordinator
    @Environment(\.metrics) private var metrics
    @State private var previewOwner = UUID()

    private var selected: AppearanceThemeCommand.Row? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                EmptyResults(text: String(localized: "No Results"))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                if index == 0 || rows[index - 1].target.appearance != row.target.appearance {
                                    SectionHeader(
                                        title: row.target.appearance == .dark
                                            ? String(localized: "Dark") : String(localized: "Light"),
                                        isFirst: index == 0)
                                }
                                ThemeCommandRow(row: row, selected: index == selection)
                                    .selectionFrame(index == selection)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        vm.selection = index
                                        coordinator.apply(row.target)
                                    }
                                    .onContinuousHover { phase in
                                        if case .active = phase, vm.hoverHighlightArmed { vm.selection = index }
                                    }
                                    .id(row.id)
                            }
                        }
                        .padding(.horizontal, metrics.spacing.md)
                        .padding(.vertical, metrics.spacing.md)
                        .hideNativeScrollers()
                        .scrollOriginAnchor()
                    }
                    .edgeDissolve()
                    .thinScrollbar()
                    .scrollFollowsSelection(scroll, row: selected?.id, atOrigin: selection == 0, proxy: proxy)
                }
            }
        }
        .onChange(of: selected?.target, initial: true) { _, _ in preview() }
        .onChange(of: vm.isVisible) { _, _ in preview() }
        .onChange(of: vm.resetToken) { _, _ in preview() }
        .onDisappear { coordinator.endPreview(owner: previewOwner) }
    }

    private func preview() {
        coordinator.previewInPalette(vm.isVisible ? selected?.target : nil, owner: previewOwner)
    }
}

private struct ThemeCommandRow: View {
    let row: AppearanceThemeCommand.Row
    let selected: Bool
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            ThemeSwatch(theme: row.target.theme)
            Text(row.title)
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Text(row.subtitle)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.md)
            if row.isSelected {
                Text("Current")
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(selected ? Theme.Colors.selection : hovered ? Theme.Colors.rowHover : .clear))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.title)
        .accessibilityValue(row.subtitle)
        .accessibilityAddTraits([.isButton])
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
