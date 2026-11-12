import Foundation

extension DictationCleanupModule: NotchcastRegistrant {
    static func register() -> [NotchcastModuleController.Entry] {
        shared.reportFailure = {
            NotchcastHost.current.showMessage(String(localized: "Could not save dictation cleanup settings.", table: "Notchcast"), .danger)
        }
        shared.load()
        return [.init(requires: [.dictationCleanup], module: shared)]
    }
}
