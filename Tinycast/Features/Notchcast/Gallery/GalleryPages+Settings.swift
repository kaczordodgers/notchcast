#if DEBUG
import SwiftUI

extension GalleryPages {
    static func settings(_ core: AppCore) -> [GalleryPage] {
        SettingsTab.allCases.filter { $0 != .notchcast }.flatMap { tab in
            [true, false].map { dark in
                settingsPage(core, tab: tab, name: "settings-\(tab.slug)-\(dark ? "dark" : "light")", dark: dark)
            }
        }
    }

    static func settingsPage(
        _ core: AppCore, tab: SettingsTab, name: String, dark: Bool, anchor: SettingsAnchor? = nil
    ) -> GalleryPage {
        let navigation = SettingsNavigationState(tab: tab)
        let presenter = SettingsEditorPresenter(core: core, navigation: navigation)
        return GalleryPage(name: name,
                           types: ["SettingsDetailView"] + (tab == .notchcast ? ["NotchcastSettingsView"] : []), makeWindow: {
            window(SettingsDetailView().settingsEnvironment(core: core, navigation: navigation, editorPresenter: presenter),
                   size: CGSize(width: 800, height: 800), dark: dark)
        }, prepare: { _ in
            if let anchor { navigation.select(tab, revealing: .section(anchor)) }
        }, settle: .seconds(1), finish: {
            if let anchor { navigation.endFlash(.section(anchor)) }
        })
    }
}
#endif
