import SwiftUI

struct DictationHistorySettingsSection: View {
    @Environment(AppCore.self) private var core
    private let preferences = NotchcastPreferences.shared
    @State private var entries: [DictationHistoryEntry] = []
    @State private var isLoading = true
    @State private var isClearing = false

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.dictationHistory) },
            set: { preferences.set(.dictationHistory, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Keep dictation history", table: "Notchcast"))
            }
        DictationHistoryList(entries: entries)
            .task {
                do {
                    let loaded = try await NotchcastCore.dictationHistory.recent(limit: 100)
                    try Task.checkCancellation()
                    entries = loaded
                } catch is CancellationError {
                    return
                } catch {
                    core.showMessage(String(localized: "Couldn’t update dictation history."), tone: .danger)
                }
                isLoading = false
            }
        Button(role: .destructive) {
            isClearing = true
            Task {
                defer { isClearing = false }
                guard await core.confirm(
                    title: String(localized: "Delete history"), message: nil,
                    symbol: "trash", confirmTitle: String(localized: "Delete history")) else { return }
                do {
                    try await NotchcastCore.dictationHistory.deleteAll()
                    entries = []
                }
                catch {
                    core.showMessage(String(localized: "Couldn’t update dictation history.", table: "Notchcast"), tone: .danger)
                }
            }
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Clear History")
        }
        .disabled(isLoading || isClearing || entries.isEmpty)
    }
}
