import Foundation

extension PasteImageModule {
    func configureFeedback(_ core: AppCore) {
        onFailure = {
            core.showMessage(String(localized:
                "Cannot paste image here. Choose a writable Finder folder and allow Automation access in System Settings."),
                tone: .danger)
        }
    }
}
