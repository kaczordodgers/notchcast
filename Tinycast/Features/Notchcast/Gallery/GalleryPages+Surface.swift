#if DEBUG
import SwiftUI

extension GalleryPages {
    static func surface(_ core: AppCore) -> [GalleryPage] {
        [AppearanceSurfaceStyle.glass, .black].flatMap { style in
            [true, false].flatMap { dark in
                let suffix = "\(style.rawValue)-\(dark ? "dark" : "light")"
                let size = CGSize(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight)
                return [
                    GalleryPage(name: "launcher-surface-\(suffix)", types: ["RootPaletteView"], makeWindow: {
                        core.appearanceCoordinator.store.setEnabled(true)
                        core.appearanceCoordinator.store.surfaceStyle = style
                        core.palette.prepare(mode: .launcher)
                        core.palette.query = ""
                        return window(RootPaletteView().paletteEnvironment(core), size: size, dark: dark)
                    }, settle: .milliseconds(500)),
                    GalleryPage(name: "dialog-surface-\(suffix)", types: ["DialogView"], makeWindow: {
                        core.appearanceCoordinator.store.setEnabled(true)
                        core.appearanceCoordinator.store.surfaceStyle = style
                        let request = DialogRequest(
                            title: "Delete this item?", message: "This cannot be undone.", symbol: "trash",
                            tone: .danger, actions: [DialogAction(title: "Cancel", role: .cancel),
                                                     DialogAction(title: "Delete", role: .destructive)],
                            defaultIndex: 1, cancelIndex: 0)
                        return window(DialogView(request: request, width: 360, onChoose: { _ in })
                            .padding(24), size: CGSize(width: 420, height: 300), dark: dark)
                    })
                ]
            }
        }
    }
}
#endif
