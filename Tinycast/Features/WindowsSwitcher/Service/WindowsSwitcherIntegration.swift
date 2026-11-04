@MainActor
enum WindowsSwitcherIntegration {
    static var enabled: Bool { NotchcastPreferences.shared.isOn(.windowsSwitcher) }

    static func apply(_ core: AppCore) -> Bool {
        guard !enabled else { return true }
        core.appIndex.setCommandsVisible([.switchWindows, .switchWindowsBackwards], false)
        core.windowSwitch.reset()
        if core.palette.mode == .switchWindows { core.palette.prepare(mode: .launcher) }
        return false
    }
}
