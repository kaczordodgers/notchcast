// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost+Live.swift
import Foundation

enum DialogTone {}
struct DialogAction {
    enum Role { case normal, cancel }
    var title: String
    var role: Role = .normal
}
enum SettingsTab { case general, notchcastMusicAndSound, notchcast }
enum SettingsSection { case notchcastSpotify, notchcastAIUsage }
enum SettingsAnchor: Equatable { case section(SettingsSection) }
struct CopyPathTarget { var processID: Int32; var bundleID: String? }
enum CopyPathSystemReader {
    enum Target { case finderSelection, browser(CopyPathTarget) }
    static func read(_ target: Target) async throws -> [String] { [] }
}
enum NotchcastCore { static func remoteResult(_ text: String) {} }

@MainActor final class AppCore {
    var appIndex: AppCore { self }
    var paletteCoordinator: AppCore { self }
    var settingsCoordinator: AppCore { self }
    var appearanceCoordinator: AppCore { self }
    var isVisible = false
    var isEnabled = false
    var hides: [Bool] = []
    var targets: [(SettingsTab, SettingsAnchor?)] = []
    var actions: [DialogAction] = []
    var defaultIndex = -1
    var selection = 0
    enum Mode { case launcher }
    func showMessage(_ text: String, tone: DialogTone) {}
    func refreshNotchcastCommands() {}
    func showPalette(mode: Mode) {}
    func hidePalette(restoreFocus: Bool) { hides.append(restoreFocus) }
    func showSettings(tab: SettingsTab, revealing: SettingsAnchor? = nil) { targets.append((tab, revealing)) }
    func showThemes() {}
    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool { false }
    func choose(title: String, message: String?, symbol: String, options: [DialogAction], defaultIndex: Int) async -> Int {
        actions = options
        self.defaultIndex = defaultIndex
        return selection
    }
}

@main struct HostLiveTests {
    @MainActor static func main() async {
        var core: AppCore? = AppCore()
        let host = NotchcastHost.live(core: core!)
        host.dismissPalette()
        precondition(core!.hides.isEmpty, "A hidden palette must stay hidden")
        core!.isVisible = true
        host.dismissPalette()
        precondition(core!.hides == [false], "Dismissal must not restore focus")
        host.showAppearanceSettings()
        host.showSpotifySettings()
        host.showLinkSettings()
        precondition(core!.targets.map(\.0) == [.general, .notchcastMusicAndSound, .notchcast])
        precondition(core!.targets.map(\.1) == [nil, .section(.notchcastSpotify), .section(.notchcastAIUsage)])
        for options in [[], ["Network", "Reconnect", "Settings"]] {
            core!.selection = options.count
            let result = await host.choose("Title", nil, "network", options, "Cancel")
            precondition(result == options.count && core!.defaultIndex == options.count)
            precondition(core!.actions.map(\.title) == options + ["Cancel"])
            precondition(core!.actions.dropLast().allSatisfy { $0.role == .normal })
            precondition(core!.actions.last?.role == .cancel)
        }
        core!.selection = 1
        let selected = await host.choose("Title", "Message", "network", ["A", "B"], "Cancel")
        precondition(selected == 1)
        core!.selection = 0
        core = nil
        let cancelled = await host.choose("Title", nil, "network", ["A"], "Cancel")
        precondition(cancelled == 1, "A released owner must cancel")
        print("PASS live host palette visibility/focus, settings targets, cancel role/default and weak owner")
    }
}
