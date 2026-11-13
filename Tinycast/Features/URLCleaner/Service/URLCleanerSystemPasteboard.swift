import AppKit

@MainActor
final class URLCleanerSystemPasteboard: URLCleanerPasteboard {
    private let pasteboard: NSPasteboard
    var writeObjects: ([any NSPasteboardWriting]) -> Bool

    init(_ pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
        writeObjects = pasteboard.writeObjects
    }
    var changeCount: Int { pasteboard.changeCount }
    var text: String? { pasteboard.string(forType: .string) }
    var isProtected: Bool {
        let types = Set(pasteboard.types ?? [])
        let items = pasteboard.pasteboardItems ?? []
        return !types.isDisjoint(with: ClipboardManager.sensitiveTypes)
            || types.contains(ClipboardManager.internalType)
            || items.count != 1
            || !Self.isPlainLink(Set(items[0].types))
    }

    // A rewrite replaces the whole item, so an image or rich text beside the link must block it.
    static func isPlainLink(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        types.isSubset(of: [.string, .URL, NSPasteboard.PasteboardType("public.url-name")])
    }

    func write(_ text: String) -> Bool {
        guard !isProtected else { return false }
        let original = self.text
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: ClipboardManager.internalType)
        pasteboard.clearContents()
        if writeObjects([item]) { return true }
        // Unmarked, so clipboard history records the restored copy as the user's own.
        if let original { pasteboard.setString(original, forType: .string) }
        return false
    }
}
