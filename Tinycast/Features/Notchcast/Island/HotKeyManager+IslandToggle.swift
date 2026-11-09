import Carbon.HIToolbox
import Foundation

extension HotKeyManager {
    /// Offered once, so a shortcut the user cleared or moved stays theirs.
    func seedIslandToggle(commandID: String, marker: UserDefaults) {
        let key = "islandToggleHotKeySeeded"
        guard !marker.bool(forKey: key) else { return }
        marker.set(true, forKey: key)
        let action = HotKeyAction.notchcastCommand(entryID: commandID)
        let chord = KeyShortcut.displayedHyperChord() ?? KeyShortcut.hyperChord(includesShift: true)
        let hyperS = HotKeyBinding.combo(KeyShortcut(
            carbonKeyCode: kVK_ANSI_S, carbonModifiers: KeyShortcut.carbonModifiers(from: chord)))
        guard binding(for: action) == nil, conflictOwner(of: hyperS, excluding: action) == nil else { return }
        setBinding(hyperS, for: action)
    }
}
