import AppKit
import Carbon.HIToolbox

extension PalettePanel {
    func notchcastPreviewOnSpace(_ event: NSEvent) -> Bool {
        let core = AppCore.shared
        let state = core.palette
        guard paletteState === state, state.mode == .fileSearch,
            !state.menuOpen, !state.isEditingField, !state.isControlListOpen
        else { return false }
        let key = event.type == .keyDown ? Int(event.keyCode) : -1
        let rows = core.fileSearch.results
        let url = rows.indices.contains(state.selection) ? rows[state.selection].url : nil
        let coordinator = QuickLookCoordinator.shared
        return coordinator.spaceInput.handle(
            screen: state.resetToken,
            arrow: key == kVK_UpArrow || key == kVK_DownArrow,
            space: key == kVK_Space,
            resetsSelection: event.type == .mouseMoved || event.type == .leftMouseDown
                || (event.type == .keyDown && key != kVK_UpArrow && key != kVK_DownArrow && key != kVK_Space),
            fileURL: url,
            hasModifiers: !event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
            isRepeat: event.type == .keyDown && event.isARepeat, isComposing: state.isComposing,
            coordinator: coordinator,
            dismiss: { core.paletteCoordinator.hidePalette(restoreFocus: false) },
            present: { coordinator.systemPreview.show($0) })
    }
}
