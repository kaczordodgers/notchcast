import AppKit

extension PaletteWindowController {
    @objc func ncQuit(_ event: NSEvent) -> NSNumber {
        guard let panel = event.window as? PalettePanel else { return false }
        return NSNumber(value: AppCore.shared.notchcastQuitSelectedWindow(event, in: panel))
    }
}

extension AppCore {
    func notchcastQuitSelectedWindow(_ event: NSEvent, in panel: PalettePanel) -> Bool {
        guard event.type == .keyDown, panel.paletteState === palette,
            SwitcherQuitKeyPolicy.consumes(
                enabled: NotchcastPreferences.shared.isOn(.switcherQuitKey),
                isSwitcher: palette.mode == .switchWindows, menuOpen: palette.menuOpen,
                composing: palette.isComposing, query: palette.query,
                character: event.charactersIgnoringModifiers?.lowercased(),
                hasModifiers: !event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]))
        else { return false }
        guard !event.isARepeat else { return true }
        let rows = windowSwitch.filtered
        guard rows.indices.contains(palette.selection) else { return true }
        windowSwitchCoordinator.quitApplication(rows[palette.selection])
        return true
    }
}
