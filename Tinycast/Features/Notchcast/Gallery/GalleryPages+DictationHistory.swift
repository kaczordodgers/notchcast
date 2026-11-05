#if DEBUG
import SwiftUI

extension GalleryPages {
    static func dictationHistory(_ core: AppCore) -> [GalleryPage] {
        [true, false].flatMap { dark in
            [false, true].map { empty in
                GalleryPage(
                    name: "settings-dictation-history-\(empty ? "empty" : "populated")-\(dark ? "dark" : "light")",
                    types: ["DictationHistoryList", "DictationHistoryRow"], makeWindow: {
                        let date = Date(timeIntervalSince1970: 1_790_000_000)
                        let entries = empty ? [] : [
                            DictationHistoryEntry(id: UUID(), date: date, raw: "Sample",
                                cleaned: "Send the updated report tomorrow morning."),
                            DictationHistoryEntry(id: UUID(), date: date.addingTimeInterval(-3600),
                                raw: "Sample", cleaned: "A longer dictation sample that wraps across multiple lines. "
                                    + "Review the draft, check the figures, and share the final notes with the team. "
                                    + "This final sentence demonstrates the two-line truncation.")
                        ]
                        return window(Form {
                            Section { DictationHistoryList(entries: entries) }
                        }.formStyle(.grouped).environment(core),
                            size: CGSize(width: 800, height: 800), dark: dark)
                    })
            }
        }
    }
}
#endif
