// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost+Live.swift
import Foundation

enum DialogTone { case success }
enum SettingsTab { case general, notchcast, notchcastMusicAndSound, notchcastTwoMacs }
struct SettingsAnchor: Equatable {
    let tab: SettingsTab
    static let notchcastAIUsage = Self(tab: .notchcastTwoMacs)
    static let notchcastSpotify = Self(tab: .notchcastMusicAndSound)
}
enum SettingsTarget { case section(SettingsAnchor) }
enum PaletteMode { case launcher }
struct DialogAction {
    enum Role { case cancel }
    let title: String
    var role: Role?
}
struct CopyPathTarget { let processID: Int32; let bundleID: String? }
enum CopyPathSource { case finderSelection, browser(CopyPathTarget) }
enum CopyPathSystemReader {
    static func read(_ source: CopyPathSource) throws -> [String] { [] }
}
@MainActor enum NotchcastCore {
    static func remoteResult(_ value: String) {}
}
@MainActor final class AppCore {
    let settingsCoordinator = SettingsCoordinator()
    let appIndex = AppIndex()
    let paletteCoordinator = PaletteCoordinator()
    let appearanceCoordinator = AppearanceCoordinator()
    func showMessage(_ value: String, tone: DialogTone) {}
    func choose(title: String, message: String?, symbol: String,
                options: [DialogAction], defaultIndex: Int) async -> Int { defaultIndex }
    func confirm(title: String, message: String, symbol: String, confirmTitle: String) async -> Bool { false }
}
@MainActor final class SettingsCoordinator {
    var tab: SettingsTab?
    var revealed: SettingsAnchor?
    func showSettings(tab: SettingsTab, revealing target: SettingsTarget? = nil) {
        self.tab = tab
        if case let .section(anchor) = target, anchor.tab == tab { revealed = anchor }
    }
}
@MainActor final class AppIndex {
    func refreshNotchcastCommands() {}
}
@MainActor final class PaletteCoordinator {
    var isVisible = false
    func showPalette(mode: PaletteMode) {}
    func hidePalette(restoreFocus: Bool) {}
}
@MainActor final class AppearanceCoordinator {
    var isEnabled = false
    func showThemes() {}
}

@main struct LinkSettingsTests {
    @MainActor static func main() {
        let core = AppCore()
        let host = NotchcastHost.live(core: core)
        host.showLinkSettings()
        precondition(core.settingsCoordinator.tab == .notchcastTwoMacs)
        precondition(core.settingsCoordinator.revealed == .notchcastAIUsage)
        host.showLinkSettings()
        precondition(core.settingsCoordinator.revealed == .notchcastAIUsage)
        print("PASS live link settings hook opens the anchor's tab and reveals the Mac Link section")
    }
}
