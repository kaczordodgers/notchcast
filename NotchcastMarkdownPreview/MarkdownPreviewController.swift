import AppKit
import QuickLookUI

@MainActor
final class MarkdownPreviewController: NSViewController, QLPreviewingController {
    private let textView = NSTextView(usingTextLayoutManager: true)
    private let fragments = NoteLayoutFragmentProvider()
    private var requestID = UUID()

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.appearance = NSAppearance(named: .darkAqua)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(
            width: Theme.Size.noteEditorInset, height: Theme.Size.noteEditorTopInset)
        textView.textLayoutManager?.delegate = fragments
        scrollView.documentView = textView
        view = scrollView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let requestID = UUID()
        self.requestID = requestID
        let document = try await MarkdownQuickLookReader.read(url)
        try Task.checkCancellation()
        guard self.requestID == requestID else { throw CancellationError() }
        loadViewIfNeeded()
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            NoteMarkdownStyler.invalidateColors()
            guard let storage = textView.textStorage else { return }
            storage.beginEditing()
            storage.setAttributedString(NSAttributedString(string: document.source))
            for index in document.markdown.lines.indices {
                let style = NoteMarkdownStyler.style(
                    at: index, in: document.markdown, text: document.source as NSString, isRevealed: false)
                storage.setAttributes(style.base, range: document.markdown.lines[index].range)
                for run in style.runs { storage.addAttributes(run.attributes, range: run.range) }
            }
            storage.endEditing()
        }
        textView.scrollToBeginningOfDocument(nil)
    }
}
