import Foundation

extension DictationCleanupModule: NotchcastRegistrant {
    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        shared.reportFailure = { [weak core] in
            core?.showMessage(String(localized: "Could not save dictation cleanup settings.", table: "Notchcast"), tone: .danger)
        }
        shared.load()
        return [.init(requires: [.dictationCleanup], module: shared)]
    }
}
