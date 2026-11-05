import SwiftUI

struct ThemeBrowserSheet: View {
    let slot: RaycastTheme.Appearance
    @Environment(AppearanceCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: String?
    @State private var previewOwner = UUID()
    @State private var host = WindowHost()

    private var sections: AppearanceThemeBrowser.Section {
        AppearanceThemeBrowser.themes(for: slot, query: query, imported: coordinator.store.imported)
    }

    private var targets: [RaycastThemeLink.Target] {
        let themes = sections.imported + sections.bundled
        let showDefault = query.isEmpty || String(localized: "Default").localizedCaseInsensitiveContains(query)
            || String(localized: "No theme", table: "Notchcast").localizedCaseInsensitiveContains(query)
        return (showDefault ? [.tinycast(slot)] : []) + themes.map { .theme($0) }
    }

    private var selectedTarget: RaycastThemeLink.Target? {
        targets.first { identity($0) == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingsFilterField(prompt: LocalizedStringResource("Search themes", table: "Notchcast"), query: $query)
                .accessibilityLabel(String(localized: "Search themes", table: "Notchcast"))
                .padding(Theme.Spacing.lg)
            if targets.isEmpty {
                EmptyResults(text: String(localized: "No Results"))
            } else {
                List(selection: $selection) {
                    if targets.contains(.tinycast(slot)) { row(.tinycast(slot)) }
                    if !sections.imported.isEmpty {
                        Section(String(localized: "Imported", table: "Notchcast")) {
                            ForEach(sections.imported) { theme in row(.theme(theme), removable: true) }
                        }
                    }
                    if !sections.bundled.isEmpty {
                        Section(String(localized: "All themes", table: "Notchcast")) {
                            ForEach(sections.bundled) { theme in row(.theme(theme)) }
                        }
                    }
                }
                .onHover { inside in
                    if !inside { coordinator.endPreview(owner: previewOwner) }
                }
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.modalAction(.standard, fillsWidth: false))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Use Theme", table: "Notchcast")) {
                    guard let selectedTarget else { return }
                    coordinator.apply(selectedTarget)
                    dismiss()
                }
                .buttonStyle(.modalAction(.primary, fillsWidth: false))
                .keyboardShortcut(.defaultAction)
                .settingsEnabled(selectedTarget != nil && coordinator.isEnabled)
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(width: AppearanceMetrics.browserWidth, height: AppearanceMetrics.browserHeight)
        .background(WindowReader { [host] in host.window = $0 })
        .motionScope()
        .onAppear {
            selection = identity(coordinator.store.theme(for: slot).map { .theme($0) } ?? .tinycast(slot))
        }
        .onChange(of: selection) { _, _ in preview(selectedTarget) }
        .onChange(of: coordinator.store.imported) { _, _ in
            if selectedTarget == nil { selection = identity(.tinycast(slot)) }
        }
        .onChange(of: query) { _, _ in
            coordinator.endPreview(owner: previewOwner)
            if selectedTarget == nil { selection = nil }
        }
        .onDisappear { coordinator.endPreview(owner: previewOwner) }
    }

    private func row(_ target: RaycastThemeLink.Target, removable: Bool = false) -> some View {
        ThemeBrowserRow(
            target: target, current: coordinator.store.theme(for: slot)?.id == target.theme?.id,
            remove: removable ? { if let theme = target.theme { coordinator.remove(theme) } } : nil
        )
        .tag(identity(target))
        .onHover { inside in
            if inside { preview(target) }
        }
    }

    private func preview(_ target: RaycastThemeLink.Target?) {
        coordinator.preview(target, owner: previewOwner, window: host.window)
    }

    private func identity(_ target: RaycastThemeLink.Target) -> String {
        target.theme?.id ?? "default:\(slot.rawValue)"
    }
}

private struct ThemeBrowserRow: View {
    let target: RaycastThemeLink.Target
    let current: Bool
    let remove: (() -> Void)?
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    private var name: String { target.theme?.name ?? String(localized: "Default") }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            ThemeSwatch(theme: target.theme)
            VStack(alignment: .leading, spacing: metrics.spacing.xxs) {
                Text(name).font(metrics.typography.rowTitle)
                Text(target.theme?.author ?? String(localized: "No theme", table: "Notchcast"))
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: metrics.spacing.md)
            if current {
                SymbolImage(name: "checkmark", size: metrics.size.menuIcon)
                    .accessibilityHidden(true)
            }
            if let remove {
                BarButton(isCompact: true, action: remove) {
                    SymbolImage(name: "xmark", size: metrics.size.menuIcon)
                }
                .opacity(hovered ? 1 : 0)
                .help(String(localized: "Remove Theme", table: "Notchcast"))
                .accessibilityLabel(String(localized: "Remove Theme", table: "Notchcast"))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue(current ? String(localized: "Current") : "")
        .accessibilityActions {
            if let remove { Button("Remove", action: remove) }
        }
    }
}

@MainActor private final class WindowHost {
    weak var window: NSWindow?
}
