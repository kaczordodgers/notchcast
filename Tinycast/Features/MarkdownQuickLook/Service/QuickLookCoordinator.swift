import Foundation
import Observation

@MainActor
@Observable
final class QuickLookCoordinator: NotchcastModule {
    private(set) var request: QuickLookRequest?
    private let preferences: NotchcastPreferences
    let spaceInput = QuickLookSpaceInput()
    let systemPreview = QuickLookSystemPresenter()

    init(preferences: NotchcastPreferences) {
        self.preferences = preferences
    }

    func start() {}

    func stop() {
        request = nil
        systemPreview.close()
    }

    @discardableResult
    func previewOnSpace(
        fileURL: URL?, selectedByArrowKeys: Bool, hasModifiers: Bool = false,
        isRepeat: Bool = false, isComposing: Bool = false, dismissLauncher: () -> Void
    ) -> Bool {
        guard let url = QuickLookSpacePolicy.file(
            fileURL, enabled: preferences.isOn(.quickLookSpace),
            selectedByArrowKeys: selectedByArrowKeys, hasModifiers: hasModifiers,
            isRepeat: isRepeat, isComposing: isComposing)
        else { return false }
        dismissLauncher()
        guard preferences.isOn(.quickLookSpace) else { return true }
        request = QuickLookRequest(id: UUID(), fileURL: url)
        return true
    }
}
