import Foundation

@MainActor
final class QuickLookSpaceInput {
    private var arrowSelection = false
    private var screen: UUID?

    func handle(
        screen: UUID, arrow: Bool, space: Bool, resetsSelection: Bool,
        fileURL: URL?, hasModifiers: Bool, isRepeat: Bool, isComposing: Bool,
        coordinator: QuickLookCoordinator, dismiss: () -> Void,
        present: (QuickLookRequest) -> Void
    ) -> Bool {
        if self.screen != screen {
            self.screen = screen
            arrowSelection = false
        }
        if resetsSelection { arrowSelection = false }
        if arrow && !hasModifiers && !isComposing { arrowSelection = true }
        guard space else { return false }
        let handled = coordinator.previewOnSpace(
            fileURL: fileURL, selectedByArrowKeys: arrowSelection,
            hasModifiers: hasModifiers, isRepeat: isRepeat, isComposing: isComposing,
            dismissLauncher: dismiss)
        if handled, let request = coordinator.request { present(request) }
        return handled
    }
}
