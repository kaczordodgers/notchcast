import SwiftUI

struct FinderSettingsSection: View {
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        if preferences.isOn(.finderCutPaste) || preferences.isOn(.finderRename) {
            Section {
                if preferences.isOn(.finderCutPaste) {
                    LabeledContent {
                        Text(verbatim: "⌘X → ⌘V")
                    } label: {
                        SettingsRowTitle(.notchcastFinder, "Cut and move files")
                        Text("A new copy or Escape cancels the cut.")
                    }
                }
                if preferences.isOn(.finderRename) {
                    LabeledContent {
                        Text(verbatim: "⌃⌥⇧⌘R")
                    } label: {
                        SettingsRowTitle(.notchcastFinder, "Rename selection")
                        Text("Uses Finder’s Return key while no text is being edited.")
                    }
                }
            } header: {
                SettingsSectionHeader(.notchcastFinder)
            }
        }
    }
}
