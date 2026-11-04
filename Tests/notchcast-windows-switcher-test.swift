// notchcast-sources: Tinycast/Features/WindowsSwitcher/Service/WindowsSwitcherIntegration.swift
import Foundation

@MainActor
final class NotchcastPreferences {
    enum Feature { case windowsSwitcher }
    static let shared = NotchcastPreferences()
    var enabled = true
    func isOn(_: Feature) -> Bool { enabled }
}

@MainActor
final class AppCore {
    enum Command { case switchWindows, switchWindowsBackwards }
    enum Mode { case launcher, switchWindows }
    final class Index {
        var hidden: [Command] = []
        func setCommandsVisible(_ commands: [Command], _ visible: Bool) {
            precondition(!visible)
            hidden = commands
        }
    }
    final class Session {
        var resets = 0
        func reset() { resets += 1 }
    }
    final class Palette {
        var mode = Mode.launcher
        func prepare(mode: Mode) { self.mode = mode }
    }
    let appIndex = Index()
    let windowSwitch = Session()
    let palette = Palette()
}

@main
@MainActor
struct WindowsSwitcherTests {
    static func main() {
        let core = AppCore()
        core.palette.mode = .switchWindows
        precondition(WindowsSwitcherIntegration.apply(core))
        precondition(core.windowSwitch.resets == 0)
        precondition(core.palette.mode == .switchWindows)
        NotchcastPreferences.shared.enabled = false
        precondition(!WindowsSwitcherIntegration.apply(core))
        precondition(core.appIndex.hidden == [.switchWindows, .switchWindowsBackwards])
        precondition(core.windowSwitch.resets == 1)
        precondition(core.palette.mode == .launcher)
        NotchcastPreferences.shared.enabled = true
        precondition(WindowsSwitcherIntegration.apply(core))
        precondition(core.windowSwitch.resets == 1)
        print("Window switcher gate passed: enabled passthrough, disable reset, re-enable.")
    }
}
