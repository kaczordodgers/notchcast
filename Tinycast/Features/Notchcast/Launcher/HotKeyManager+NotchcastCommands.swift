import Foundation

extension HotKeyManager {
    /// `setBinding` re-registers through the switch guard, so a feature turned off frees its combos.
    func syncNotchcastCommands() {
        for entry in NotchcastCommandCatalog.entries {
            let action = HotKeyAction.notchcastCommand(entryID: entry.id)
            if let binding = binding(for: action) { setBinding(binding, for: action) }
        }
    }
}
