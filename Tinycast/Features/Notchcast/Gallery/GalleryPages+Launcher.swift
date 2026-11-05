#if DEBUG
import SwiftUI

extension GalleryPages {
    static func launcher(_ core: AppCore) -> [GalleryPage] {
        shortenLink(core) + [true, false].flatMap { dark in
            ["root", "results", "number-keys", "empty"].map { state in
                GalleryPage(name: "launcher-\(state)-\(dark ? "dark" : "light")",
                            types: ["RootPaletteView", "LauncherList"]
                                + (state == "empty" ? [] : ["SectionHeader", "AppRow", "AppIconView"]),
                            makeWindow: {
                    NotchcastPreferences.shared.set(.smallCommands, false)
                    core.appIndex.refreshNotchcastCommands()
                    let commands = ["Sample Notes", "Sample Calendar", "Sample Files"].map {
                        CustomCommand(name: $0, command: "true")
                    }
                    core.appIndex.setCustomCommands(commands)
                    core.palette.prepare(mode: .launcher)
                    core.palette.query = state == "root" ? "" : (state == "empty" ? "zzzznomatches" : "sample")
                    NotchcastPreferences.shared.set(.launcherNumberKeys, state == "number-keys")
                    core.palette.noteCommandHeld(state == "number-keys")
                    return window(RootPaletteView().paletteEnvironment(core),
                                  size: CGSize(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight), dark: dark)
                }, settle: .milliseconds(500))
            }
        }
    }
    private static func shortenLink(_ core: AppCore) -> [GalleryPage] {
        [true, false].map { dark in
            GalleryPage(name: "launcher-shorten-link-\(dark ? "dark" : "light")",
                        types: ["RootPaletteView", "LauncherList", "SectionHeader", "AppRow", "AppIconView",
                                "InlineArgumentFields"],
                        makeWindow: {
                NotchcastPreferences.shared.set(.smallCommands, true)
                NotchcastPreferences.shared.set(.launcherNumberKeys, false)
                core.appIndex.refreshNotchcastCommands()
                core.appIndex.setCustomCommands([])
                core.palette.prepare(mode: .launcher)
                core.palette.noteCommandHeld(false)
                core.palette.query = "shorten link"
                return window(RootPaletteView().paletteEnvironment(core),
                              size: CGSize(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight), dark: dark)
            }, settle: .milliseconds(500))
        }
    }
}
#endif
