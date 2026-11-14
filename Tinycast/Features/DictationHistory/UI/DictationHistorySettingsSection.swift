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
    @State private var hasQuarantine = false
    @State private var confirmingClear = false

    private var reloadID: String {
        "\(preferences.isOn(.dictationHistory))-\(DictationHistoryModule.shared.revision)"
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
                    let loaded = try await DictationHistoryModule.shared.snapshot(limit: 100)
                    try Task.checkCancellation()
                    entries = loaded.entries
                    hasQuarantine = loaded.hasQuarantine
                } catch is CancellationError {
                    return
                } catch {
                    loadFailed = true
                    core.showMessage(String(localized: "Couldn’t update dictation history.", table: "Notchcast"), tone: .danger)
                }
                isLoading = false
            }
        Button(role: .destructive) {
            confirmingClear = true
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, "Clear History")
        }
        .disabled(!DictationHistoryClearPolicy.isEnabled(
            isLoading: isLoading, isClearing: isClearing, isEmpty: entries.isEmpty,
            hasQuarantine: hasQuarantine, loadFailed: loadFailed))
        .confirmationDialog(
            String(localized: "Clear dictation history?", table: "Notchcast"),
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Clear History"), role: .destructive) { clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(localized: "Every past dictation goes. This can't be undone.", table: "Notchcast"))
        }
    }

    private func clear() {
        isClearing = true
        Task {
            defer { isClearing = false }
            do {
                try await DictationHistoryModule.shared.deleteAll()
                entries = []
                hasQuarantine = false
                loadFailed = false
            } catch {
                core.showMessage(String(localized: "Couldn’t update dictation history.", table: "Notchcast"), tone: .danger)
            }
        }
    }
}
