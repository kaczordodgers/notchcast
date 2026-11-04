#if DEBUG
import SwiftUI

extension GalleryPages {
    static func launcher(_ core: AppCore) -> [GalleryPage] {
        [true, false].flatMap { dark in
            ["root", "results", "empty"].map { state in
                GalleryPage(name: "launcher-\(state)-\(dark ? "dark" : "light")",
                            types: ["RootPaletteView", "LauncherList"]
                                + (state == "empty" ? [] : ["SectionHeader", "AppRow", "AppIconView"]),
                            makeWindow: {
                    let commands = ["Sample Notes", "Sample Calendar", "Sample Files"].map {
                        CustomCommand(name: $0, command: "true")
                    }
                    core.appIndex.setCustomCommands(commands)
                    core.palette.prepare(mode: .launcher)
                    core.palette.query = state == "root" ? "" : (state == "empty" ? "zzzznomatches" : "sample")
                    return window(RootPaletteView().paletteEnvironment(core),
                                  size: CGSize(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight), dark: dark)
                })
            }
        }
    }
}
#endif
