import SwiftUI

struct AppearanceSettingsSection: View {
    @Environment(AppearanceCoordinator.self) private var coordinator
    private let preferences = NotchcastPreferences.shared
    @State private var choosingTheme = false
    @State private var slot = RaycastTheme.Appearance.dark
    @State private var link = ""

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferences.isOn(.appearance) },
                set: { preferences.set(.appearance, $0) })
            ) {
                SettingsFeatureToggleLabel(
                    anchor: .notchcastAppearance, title: "Custom appearance",
                    subtitle: "Themes and surface styles for the launcher, dialogs and HUDs.")
            }
            Group {
                SettingsRow(
                    title: "Surface", subtitle: String(localized: "How the launcher, dialogs and HUDs are drawn."),
                    anchor: .notchcastAppearance
                ) {
                    SteadySegmentedPicker(
                        title: String(localized: "Surface"),
                        options: AppearanceSurfaceStyle.allCases.map { .init(value: $0, title: $0.title) },
                        selection: Binding(get: { coordinator.store.surfaceStyle }, set: coordinator.setSurface))
                }
                AppearanceThemeSlotRow(slot: .light, theme: coordinator.store.light) { choose(.light) }
                AppearanceThemeSlotRow(slot: .dark, theme: coordinator.store.dark) { choose(.dark) }
                LabeledContent {
                    HStack(spacing: Theme.Spacing.md) {
                        Slider(
                            value: Binding(get: { coordinator.store.backgroundOpacity }, set: coordinator.setOpacity),
                            in: 0.2...1, step: 0.05
                        ) {
                            Text("Theme backdrop")
                        }
                        Text(coordinator.store.backgroundOpacity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: Theme.Size.volumeReadout, alignment: .trailing)
                    }
                } label: {
                    SettingsRowTitle(.notchcastAppearance, "Theme backdrop")
                    Text("How strongly the theme's background shows through.")
                }
                .settingsEnabled(coordinator.store.light != nil || coordinator.store.dark != nil)
                LabeledContent {
                    TextField("", text: $link, prompt: Text(verbatim: "raycast://theme?…"))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Theme link")
                    Button("Import") { coordinator.importLink(link) }
                        .settingsEnabled(!link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } label: {
                    SettingsRowTitle(.notchcastAppearance, "Import from link")
                }
            }
            .settingsEnabled(coordinator.isEnabled)
        } header: {
            SettingsSectionHeader(.notchcastAppearance)
        }
        .sheet(isPresented: $choosingTheme) {
            ThemeBrowserSheet(slot: slot)
                .environment(coordinator)
        }
        .onChange(of: coordinator.isEnabled) { _, enabled in
            if !enabled { choosingTheme = false }
        }
    }

    private func choose(_ slot: RaycastTheme.Appearance) {
        self.slot = slot
        choosingTheme = true
    }
}

private struct AppearanceThemeSlotRow: View {
    let slot: RaycastTheme.Appearance
    let theme: RaycastTheme?
    let choose: () -> Void

    private var title: LocalizedStringResource { slot == .dark ? "Dark theme" : "Light theme" }
    private var name: String { theme?.name ?? String(localized: "Default") }

    var body: some View {
        SettingsRow(title: title, anchor: .notchcastAppearance) {
            HStack(spacing: Theme.Spacing.md) {
                ThemeSwatch(theme: theme)
                Text(name).foregroundStyle(.secondary).lineLimit(1)
                Button("Choose…", action: choose)
                    .accessibilityLabel(slot == .dark
                        ? String(localized: "Choose dark theme") : String(localized: "Choose light theme"))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(name)
    }
}
