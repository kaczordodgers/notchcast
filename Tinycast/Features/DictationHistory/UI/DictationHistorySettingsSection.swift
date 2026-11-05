import SwiftUI

struct DictationHistorySettingsSection: View {
    @Environment(AppCore.self) private var core
    private let preferences = NotchcastPreferences.shared

    var body: some View {
        Toggle(isOn: Binding(
            get: { preferences.isOn(.dictationHistory) },
            set: { preferences.set(.dictationHistory, $0) })) {
                SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Keep dictation history", table: "Notchcast"))
            }
        Button {
            Task {
                guard await core.confirm(
                    title: String(localized: "Delete history", table: "Notchcast"), message: nil,
                    symbol: "trash", confirmTitle: String(localized: "Delete history", table: "Notchcast")) else { return }
                do { try await NotchcastCore.dictationHistory.deleteAll() }
                catch {
                    core.showMessage(String(localized: "Couldn’t update dictation history.", table: "Notchcast"), tone: .danger)
                }
            }
        } label: {
            SettingsRowTitle(.notchcastCaptureAndDictation, LocalizedStringResource("Delete history", table: "Notchcast"))
        }
    }
}
