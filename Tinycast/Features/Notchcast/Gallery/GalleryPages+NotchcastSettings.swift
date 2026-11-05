#if DEBUG
import SwiftUI

extension GalleryPages {
    static func notchcastSettings(_ core: AppCore) -> [GalleryPage] {
        let modules = NotchcastSettingsModule.allCases.filter { !$0.visibleGroups.isEmpty }.flatMap { module in
            [true, false].map { dark in
                settingsPage(core, tab: module.tab,
                             name: "settings-notchcast-\(module.rawValue)-\(dark ? "dark" : "light")", dark: dark)
            }
        }
        let pricing = [true, false].map { dark in
            GalleryPage(name: "settings-notchcast-agent-pricing-\(dark ? "dark" : "light")",
                        types: ["AgentPricingSettingsSection"], makeWindow: {
                let navigation = SettingsNavigationState(tab: NotchcastSettingsModule.aiAndAgents.tab)
                let presenter = SettingsEditorPresenter(core: core, navigation: navigation)
                return window(Form { AgentPricingSettingsSection() }.formStyle(.grouped)
                    .settingsEnvironment(core: core, navigation: navigation, editorPresenter: presenter),
                              size: CGSize(width: 800, height: 800), dark: dark)
            })
        }
        return modules + pricing + settingsBackupCopies + shelfReceived(core)
    }
}
#endif
