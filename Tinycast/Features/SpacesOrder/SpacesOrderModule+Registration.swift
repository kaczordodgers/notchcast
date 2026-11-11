import Foundation

extension SpacesOrderModule: NotchcastRegistrant {
    static let shared = SpacesOrderModule()

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        shared.onFailure = { [weak core] in
            core?.showMessage(String(localized: "Could not update Spaces ordering.", table: "Notchcast"), tone: .danger)
        }
        shared.restoreIfDisabled()
        return [.init(requires: [.spacesOrder], module: shared)]
    }
}
