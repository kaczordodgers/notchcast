import AppKit

@MainActor
final class URLCleanerSystemPasteboard: URLCleanerPasteboard {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard) { self.pasteboard = pasteboard }
    var changeCount: Int { pasteboard.changeCount }
    var text: String? { pasteboard.string(forType: .string) }
    var isProtected: Bool {
        let types = Set(pasteboard.types ?? [])
        return !types.isDisjoint(with: ClipboardManager.sensitiveTypes)
            || types.contains(ClipboardManager.internalType)
            || pasteboard.pasteboardItems?.count != 1
            || !Self.isPlainLink(types)
    }

    // A rewrite replaces the whole item, so an image or rich text beside the link must block it.
    static func isPlainLink(_ types: Set<NSPasteboard.PasteboardType>) -> Bool {
        types.isSubset(of: [.string, .URL, NSPasteboard.PasteboardType("public.url-name")])
    }

    func write(_ text: String) -> Bool {
        guard !isProtected else { return false }
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: ClipboardManager.internalType)
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }
}
