import SwiftUI

struct GitHubTokenSettingRow: View {
    @State private var token = ""
    @State private var status = String(localized: "Not configured")

    var body: some View {
        LabeledContent("GitHub Token") {
            VStack(alignment: .leading) {
                SecureField("GitHub Token", text: $token)
                    .settingsEditorTextField()
                HStack {
                    Button("Save") { updateToken(remove: false) }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Remove") { updateToken(remove: true) }
                    Text(status)
                }
            }
        }
        .task { readStatus() }
    }

    private func updateToken(remove: Bool) {
        do {
            let store = KeychainSecretStore(scope: "github")
            if remove {
                try store.removeSecret(for: GitHubModule.account)
            } else {
                try store.setSecret(token.trimmingCharacters(in: .whitespacesAndNewlines), for: GitHubModule.account)
            }
            token = ""
            readStatus()
        } catch {
            status = String(localized: "Unavailable")
        }
    }

    private func readStatus() {
        do {
            status = try KeychainSecretStore(scope: "github").hasSecret(for: GitHubModule.account)
                ? String(localized: "Configured") : String(localized: "Not configured")
        } catch {
            status = String(localized: "Unavailable")
        }
    }
}

struct AppearanceSurfaceSettingRow: View {
    @Environment(AppearanceCoordinator.self) private var coordinator

    var body: some View {
        SettingsRow(
            title: "Surface", subtitle: String(localized: "How the launcher, dialogs and HUDs are drawn."),
            anchor: .notchcastAppearance
        ) {
            SteadySegmentedPicker(
                title: String(localized: "Surface"),
                options: AppearanceSurfaceStyle.allCases.map { .init(value: $0, title: $0.title) },
                selection: Binding(get: { coordinator.store.surfaceStyle }, set: coordinator.setSurface))
        }

    }
}

struct AppearanceLightThemeSettingRow: View {
    var body: some View {
        AppearanceThemeChoiceRow(slot: .light)
    }
}

struct AppearanceDarkThemeSettingRow: View {
    var body: some View {
        AppearanceThemeChoiceRow(slot: .dark)
    }
}

private struct AppearanceThemeChoiceRow: View {
    @Environment(AppearanceCoordinator.self) private var coordinator
    @State private var choosingTheme = false
    let slot: RaycastTheme.Appearance

    var body: some View {
        AppearanceThemeSlotRow(slot: slot, theme: slot == .light ? coordinator.store.light : coordinator.store.dark) {
            choosingTheme = true
        }
        .sheet(isPresented: $choosingTheme) {
            ThemeBrowserSheet(slot: slot).environment(coordinator)
        }
        .onChange(of: coordinator.isEnabled) { _, enabled in
            if !enabled { choosingTheme = false }
        }
    }
}

struct AppearanceOpacitySettingRow: View {
    @Environment(AppearanceCoordinator.self) private var coordinator

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.md) {
                Slider(
                    value: Binding(get: { coordinator.store.backgroundOpacity }, set: coordinator.setOpacity),
                    in: 0.2...1, step: 0.05
                ) {
                    Text("Theme backdrop")
                }
                .labelsHidden()
                .accessibilityLabel("Theme backdrop")
                Text(coordinator.store.backgroundOpacity, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: Theme.Size.volumeReadout, alignment: .trailing)
            }
        } label: {
            SettingsRowTitle(.notchcastAppearance, "Theme backdrop")
            Text("How strongly the theme's background shows through.")
        }
        .settingsEnabled(coordinator.store.light != nil || coordinator.store.dark != nil)

    }
}

struct AppearanceImportSettingRow: View {
    @Environment(AppearanceCoordinator.self) private var coordinator
    @State private var link = ""

    var body: some View {
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
