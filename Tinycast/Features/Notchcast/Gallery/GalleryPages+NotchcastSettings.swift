#if DEBUG
import SwiftUI

extension GalleryPages {
    static func notchcastSettings(_ core: AppCore) -> [GalleryPage] {
        let groups: [(String, SettingsAnchor)] = [
            ("island", .notchcastIsland), ("island-options", .notchcastOptions),
            ("launcher", .notchcastLauncher), ("system", .notchcastSystem),
            ("activities", .notchcastActivities), ("system-tools", .notchcastMonitor),
            ("clean", .notchcastClean), ("tools", .notchcastDownloads),
            ("tweaks", .notchcastTweaks), ("music", .notchcastMusic),
            ("tasks", .notchcastTasks), ("torrents", .notchcastTorrents),
            ("archives", .notchcastArchives), ("clipboard", .notchcastPaste),
            ("finder", .notchcastFinder), ("capture-and-dictation", .notchcastCaptureAndDictation),
            ("build-stats", .notchcastBuildStats)
        ]
        let anchored = groups.flatMap { group, anchor in
            [true, false].map { dark in
                settingsPage(core, tab: .notchcast,
                             name: "settings-notchcast-\(group)-\(dark ? "dark" : "light")",
                             dark: dark, anchor: anchor)
            }
        }
        let pricing = [true, false].map { dark in
            GalleryPage(name: "settings-notchcast-agent-pricing-\(dark ? "dark" : "light")",
                        types: ["AgentPricingSettingsSection"], makeWindow: {
                let navigation = SettingsNavigationState(tab: .notchcast)
                let presenter = SettingsEditorPresenter(core: core, navigation: navigation)
                return window(Form { AgentPricingSettingsSection() }.formStyle(.grouped)
                    .settingsEnvironment(core: core, navigation: navigation, editorPresenter: presenter),
                              size: CGSize(width: 800, height: 800), dark: dark)
            })
        }
        return anchored + pricing
    }
}
#endif
