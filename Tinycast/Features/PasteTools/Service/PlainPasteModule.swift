import AppKit

@MainActor
final class PlainPasteModule: NotchcastModule {
    private let clipboard: ClipboardManager
    private var pending: (items: [NSPasteboardItem], count: Int)?
    private var restore: Task<Void, Never>?

    init(clipboard: ClipboardManager) { self.clipboard = clipboard }

    func start() {}

    func stop() {
        finish()
    }

    func paste() {
        guard NotchcastPreferences.shared.isOn(.pastePlain), Permissions.isAccessibilityTrusted() else { return }
        finish()
        let board = NSPasteboard.general
        guard board.types?.contains(.fileURL) != true,
            let text = board.string(forType: .string)
                ?? ClipboardManager.plainText(fromRichTextOn: board)
                ?? board.data(forType: .rtfd).flatMap({ NSAttributedString(rtfd: $0, documentAttributes: nil)?.string })
        else {
            Paster.postCommandV()
            return
        }
        let originals = (board.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        clipboard.prepareForTinycastPasteboardMutation()
        Paster.copyString(text)
        pending = (originals, board.changeCount)
        Paster.postCommandV()
        restore = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.finish()
        }
    }

    private func finish() {
        restore?.cancel()
        restore = nil
        guard let pending else { return }
        self.pending = nil
        let board = NSPasteboard.general
        guard board.changeCount == pending.count else { return }
        board.clearContents()
        board.writeObjects(pending.items)
        clipboard.synchronizeAfterTinycastPasteboardMutation(changeCount: board.changeCount)
    }
}
