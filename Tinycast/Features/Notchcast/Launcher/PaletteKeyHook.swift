import AppKit

extension PaletteWindowController {
    /// The palette panel's one fork hook; upstream's panel calls this selector, so the name stays.
    @objc func ncQuit(_ event: NSEvent) -> NSNumber {
        guard let panel = event.window as? PalettePanel else { return false }
        if panel.notchcastPreviewOnSpace(event) { return true }
        return NSNumber(value: AppCore.shared.notchcastQuitSelectedWindow(event, in: panel))
    }
}
