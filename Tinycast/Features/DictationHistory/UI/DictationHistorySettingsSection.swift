import SwiftUI

extension EnvironmentValues {
    @Entry var dictationHistorySampleEntries: [DictationHistoryEntry]? = nil
}

struct DictationHistorySettingRow: View {
    @Environment(AppCore.self) private var core
    @Environment(\.dictationHistorySampleEntries) private var sampleEntries
    private let preferences = NotchcastPreferences.shared
    @State private var entries: [DictationHistoryEntry] = []
    @State private var isLoading = true
    @State private var isClearing = false
    @State private var loadFailed = false

    private var reloadID: String {
        "\(preferences.isOn(.dictationHistory))-\(NotchcastCore.dictationHistory.revision)"
    }

    var body: some View {
        DictationHistoryList(entries: entries)
            .task(id: reloadID) {
                if let sampleEntries {
                    entries = sampleEntries
                    isLoading = false
                    return
                }
                isLoading = true
                loadFailed = false
                do {
                    let loaded = try await NotchcastCore.dictationHistory.recent(limit: 100)
                    try Task.checkCancellation()
                    entries = loaded
                } catch is CancellationError {
                    return
                } catch {
                    loadFailed = true
                    core.showMessage(String(localized: "Couldn’t update dictation history.", table: "Notchcast"), tone: .danger)
                }
                isLoading = false
            }
        Button(role: .destructive) {
            isClearing = true
            Task {
                defer { isClearing = false }
                guard await core.confirm(
                    title: String(localized: "Clear dictation history?", table: "Notchcast"),
                    message: String(localized: "Every past dictation goes. This can't be undone.", table: "Notchcast"),
                    symbol: "waveform", confirmTitle: String(localized: "Clear History")) else { return }
                do {
                    try await NotchcastCore.dictationHistory.deleteAll()
                    entries = []
                    loadFailed = false
                }
                catch {
                    core.showMessage(String(localized: "Couldn’t update dictation history.", table: "Notchcast"), tone: .danger)
                }
            }
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Clear History")
        }
        .disabled(!DictationHistoryClearPolicy.isEnabled(
            isLoading: isLoading, isClearing: isClearing, isEmpty: entries.isEmpty, loadFailed: loadFailed))
    }
}
