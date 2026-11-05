#if DEBUG
import SwiftUI

extension GalleryPages {
    static func dictationHistory(_ core: AppCore) -> [GalleryPage] {
        [true, false].flatMap { dark in
            [false, true].map { empty in
                GalleryPage(
                    name: "settings-dictation-history-\(empty ? "empty" : "populated")-\(dark ? "dark" : "light")",
                    types: ["NotchcastModuleSettingsView", "DictationHistorySettingRow"], makeWindow: {
                        let date = Date(timeIntervalSince1970: 1_790_000_000)
                        let entries = empty ? [] : [
                            DictationHistoryEntry(id: UUID(), date: date, raw: "Sample",
                                cleaned: "Send the updated report tomorrow morning."),
                            DictationHistoryEntry(id: UUID(), date: date.addingTimeInterval(-3600),
                                raw: "Sample", cleaned: "A longer dictation sample that wraps across multiple lines. "
                                    + "Review the draft, check the figures, and share the final notes with the team. "
                                    + "This final sentence demonstrates the two-line truncation.")
                        ]
                        let navigation = SettingsNavigationState(tab: NotchcastSettingsModule.dictation.tab)
                        let presenter = SettingsEditorPresenter(core: core, navigation: navigation)
                        return window(NotchcastModuleSettingsView(module: .dictation)
                            .environment(\.dictationHistorySampleEntries, entries)
                            .settingsEnvironment(core: core, navigation: navigation, editorPresenter: presenter),
                            size: CGSize(width: 800, height: 800), dark: dark)
                    })
            }
        }
    }
}
#endif
