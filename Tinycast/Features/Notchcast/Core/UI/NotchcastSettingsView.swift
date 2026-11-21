import SwiftUI

/// A Notchcast tab: one section per category it holds, built only from those add-ons.
struct NotchcastSettingsView: View {
    let controller: NotchcastController
    let pane: NotchcastPane

    var body: some View {
        Form {
            if pane == .island {
                NotchcastIslandSettingsRows()
                NotchcastLookSection(looks: AppCore.shared.island.looks)
            }
            ForEach(pane.categories, id: \.self) { category in
                let switches = controller.switches.filter { $0.category == category }
                if !switches.isEmpty {
                    let anchor = NotchcastSettingsSearch.anchor(category)
                    Section {
                        ForEach(switches) { item in
                            NotchcastSwitchRows(controller: controller, item: item, anchor: anchor)
                        }
                    } header: {
                        SettingsSectionHeader(anchor)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notchcast(pane))
        .onAppear { controller.hub.refreshPermission() }
    }
}

/// A switch, then its commands' alias, hotkey and launcher fields and its extra rows while it is on.
private struct NotchcastSwitchRows: View {
    let controller: NotchcastController
    let item: NotchcastSwitch
    let anchor: SettingsAnchor

    private var preferences: NotchcastPreferences { controller.preferences }

    private var dependenciesMet: Bool { item.dependencies.allSatisfy(preferences.isEnabled) }

    private var needsAccessibility: Bool {
        item.requiredGrants.contains(.accessibility) && !controller.hub.isTrusted
    }

    var body: some View {
        Toggle(isOn: Binding(get: { preferences.isOn(item.id) }, set: { preferences.set(item.id, on: $0) })) {
            SettingsRowTitle(anchor, verbatim: item.title)
            if !item.subtitle.isEmpty { Text(item.subtitle) }
        }
        .settingsEnabled(dependenciesMet)
        if preferences.isEnabled(item.id), needsAccessibility {
            LabeledContent {
                Button("Grant Access…") { Permissions.openAccessibilitySettings() }
            } label: {
                Label(
                    String(localized: "Needs Accessibility access", table: "Notchcast"),
                    systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        if preferences.isEnabled(item.id) {
            ForEach(controller.slots.flatMap { $0.addon.commands }.filter { $0.switchID == item.id }) { command in
                let shown = preferences.showsInLauncher(command.id)
                // Not SettingsRow: its one-line title truncates beside the three controls.
                NotchcastCommandRow {
                    Text(command.name)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: NotchcastCommandRowLayout.titleMinimum, alignment: .leading)
                        .opacity(shown ? 1 : 0.45)
                } trailing: {
                    EmptyView()
                } controls: {
                    AliasField(key: command.id, name: command.name)
                    ShortcutRecorder(action: .notchcastCommand(entryID: command.id))
                    Toggle(isOn: Binding(get: { shown }, set: { preferences.setShowsInLauncher(command.id, $0) })) {
                        NotchcastLauncherCheckboxLabel(title: Text("Show in launcher"))
                    }
                        .toggleStyle(.checkbox)
                        .launcherVisibilityHelp()
                        .accessibilityLabel(
                            String(localized: "Show \(command.name) in the launcher", table: "Notchcast"))
                }
            }
            if let context = controller.context(forSwitch: item.id) {
                ForEach(controller.slots.flatMap(\.settings).filter { $0.row.switchID == item.id }) { entry in
                    entry.row.view(context)
                }
            }
        }
    }
}
