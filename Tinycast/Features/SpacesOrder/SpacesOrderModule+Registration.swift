import Foundation

extension SpacesOrderModule: NotchcastRegistrant {
    static let shared = SpacesOrderModule()

    static func register() -> [NotchcastModuleController.Entry] {
        shared.onFailure = {
            NotchcastHost.current.showMessage(String(localized: "Could not update Spaces ordering.", table: "Notchcast"), .danger)
        }
        shared.restoreIfDisabled()
        return [.init(requires: [.spacesOrder], module: shared)]
    }
}
