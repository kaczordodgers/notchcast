import Foundation

extension DictationHistoryModule: NotchcastRegistrant {
    static let shared = DictationHistoryModule(
        repository: .init(directory: NotchcastIdentity.supportRoot.appendingPathComponent("DictationHistory"), now: Date.init))

    static func register() -> [NotchcastModuleController.Entry] {
        shared.onFailure = {
            NotchcastHost.current.showMessage(String(localized: "Couldn’t update dictation history.", table: "Notchcast"), .danger)
        }
        DictationFamily.shared.historySink = { raw, cleaned in
            shared.enqueue(raw: raw, cleaned: cleaned)
        }
        shared.setStageEnabled = { DictationFamily.shared.setHistory($0) }
        Task { await shared.maintain() }
        return [.init(requires: [.dictationHistory], module: shared)]
    }
}
