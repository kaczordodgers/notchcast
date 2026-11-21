import SwiftUI

/// The Island tab's rows; the island shell's own settings live here, so the tab needs no add-on.
struct NotchcastIslandSettingsRows: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle(isOn: $settings.islandShowsInCaptures) {
                SettingsRowTitle(NotchcastSettingsSearch.island, NotchcastSettingsSearch.showsInCaptures)
                Text("Off hides every Notchcast window: the island, launcher, questions, reports and this Settings window.",
                     tableName: "Notchcast")
            }
            Toggle(isOn: $settings.islandOutlineWhenOpen) {
                SettingsRowTitle(NotchcastSettingsSearch.island, NotchcastSettingsSearch.outlineWhenOpen)
                Text("A faint line around the open island in Dark.", tableName: "Notchcast")
            }
            Toggle(isOn: $settings.islandOpensOnHover) {
                SettingsRowTitle(NotchcastSettingsSearch.island, NotchcastSettingsSearch.opensOnHover)
            }
            Picker(selection: $settings.islandPosition) {
                Text("Top edge", tableName: "Notchcast").tag(IslandPosition.topEdge)
                Text("Menu bar center", tableName: "Notchcast").tag(IslandPosition.menuBarCenter)
                Text("Menu bar bottom", tableName: "Notchcast").tag(IslandPosition.menuBarBottom)
            } label: {
                SettingsRowTitle(NotchcastSettingsSearch.island, NotchcastSettingsSearch.position)
            }
        } header: {
            SettingsSectionHeader(NotchcastSettingsSearch.island)
        }
    }
}
