#if DEBUG
import SwiftUI

extension GalleryPages {
    static func shelfReceived(_ core: AppCore) -> [GalleryPage] {
        [true, false].flatMap { dark in
            [true, false].map { empty in
                GalleryPage(name: "shelf-received-\(empty ? "empty" : "items")-\(dark ? "dark" : "light")",
                            types: ["ShelfReceivedRows"], makeWindow: {
                    let entries = empty ? [] : [
                        ShelfReceivedEntry(item: ShelfItem(kind: .text, name: "Text",
                            data: Data("A note from the other Mac".utf8)), receivedAt: .now),
                        ShelfReceivedEntry(item: ShelfItem(kind: .file, name: "Report.pdf",
                            data: Data("Sample".utf8)), receivedAt: .now)
                    ]
                    return window(Form {
                        Section(String(localized: "Shelf between Macs", table: "Notchcast")) {
                            ShelfReceivedRows(entries: entries, action: { _, _ in })
                        }
                    }.formStyle(.grouped), size: CGSize(width: 800, height: 600), dark: dark)
                })
            }
        }
    }
}
#endif
