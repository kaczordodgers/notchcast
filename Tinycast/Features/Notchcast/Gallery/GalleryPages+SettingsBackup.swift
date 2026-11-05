#if DEBUG
import SwiftUI

extension GalleryPages {
    static var settingsBackupCopies: [GalleryPage] {
        [true, false].map { dark in
            GalleryPage(name: "settings-backup-copies-\(dark ? "dark" : "light")",
                        types: ["ForkSettingsBackupCopiesView"], makeWindow: {
                window(Form {
                    Section {
                        ForkSettingsBackupCopiesView(copies: [
                            .init(name: "settings-v2-2.plist", date: Date(timeIntervalSince1970: 172800), size: 2048, valid: true),
                            .init(name: "settings-v2-1.plist", date: Date(timeIntervalSince1970: 86400), size: nil, valid: false)
                        ], restore: { _ in })
                    } header: {
                        Text(verbatim: "Settings backup")
                    }
                    Section { ForkSettingsBackupCopiesView(copies: [], restore: { _ in }) }
                }.formStyle(.grouped), size: CGSize(width: 800, height: 600), dark: dark)
            })
        }
    }
}
#endif
