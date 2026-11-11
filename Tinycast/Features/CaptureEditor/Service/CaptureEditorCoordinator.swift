import AppKit

@MainActor
final class CaptureEditorCoordinator: NotchcastModule {
    @MainActor
    protocol Host: AnyObject {
        func openEditor(_ document: CaptureEditorDocument, image: CaptureEditorImage)
        func closeEditor()
    }

    enum Failure: LocalizedError {
        case disabled
        case noImage
        case clipboard

        var errorDescription: String? {
            switch self {
            case .disabled: String(localized: "Capture is disabled.", table: "Notchcast")
            case .noImage: String(localized: "No Image to Edit", table: "Notchcast")
            case .clipboard: String(localized: "Could not copy to clipboard.", table: "Notchcast")
            }
        }
    }

    private struct Session {
        let document: CaptureEditorDocument
        let image: CaptureEditorImage
        let source: NSImage?
        let clipboardCount: Int?
    }

    weak var host: (any Host)?
    private(set) var enabled = false
    private(set) var isOpen = false
    private(set) var copyFailure: (any Error)?
    var document: CaptureEditorDocument? { session?.document }
    var lastCapture: NSImage? {
        didSet {
            guard lastCapture !== oldValue else { return }
            close()
            session = nil
        }
    }
    private let pasteboard: NSPasteboard
    private let render: @MainActor (CaptureEditorImage, [CaptureEditorMark]) async throws -> Data
    private var session: Session?
    private var previewFailing = false
    private var operation: UUID?
    private var copyTask: Task<Void, Never>?
    private let reportFailure: (@MainActor (any Error) -> Void)?

    init(pasteboard: NSPasteboard = .general, host: (any Host)? = nil,
         render: @escaping @MainActor (CaptureEditorImage, [CaptureEditorMark]) async throws -> Data = {
             try await CaptureEditorRender.png($0, marks: $1)
         },
         reportFailure: (@MainActor (any Error) -> Void)? = nil) {
        self.pasteboard = pasteboard
        self.host = host
        self.render = render
        self.reportFailure = reportFailure
    }

    deinit { copyTask?.cancel() }

    func start() { enabled = true }

    func stop() {
        enabled = false
        close()
        session = nil
    }

    func open(image: NSImage) throws {
        guard enabled else { throw Failure.disabled }
        if let session, session.source === image {
            present(session)
            return
        }
        guard let editable = CaptureEditorImage(image) else { throw Failure.noImage }
        present(makeSession(image: editable, source: image, clipboardCount: pasteboard.changeCount))
    }

    func openFromClipboardOrLast() throws {
        guard enabled else { throw Failure.disabled }
        let count = pasteboard.changeCount
        if let session, session.clipboardCount == count {
            present(session)
        } else if let image = pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
                  let editable = CaptureEditorImage(image) {
            present(makeSession(image: editable, source: nil, clipboardCount: count))
        } else if let lastCapture {
            try open(image: lastCapture)
        } else {
            throw Failure.noImage
        }
    }

    func openCapture(url: URL?, clipboard: Bool) throws {
        if let url, let image = NSImage(contentsOf: url) {
            try open(image: image)
        } else if url == nil, clipboard {
            try openFromClipboardOrLast()
        } else {
            throw Failure.noImage
        }
    }

    func close() {
        copyTask?.cancel()
        copyTask = nil
        operation = nil
        guard isOpen else { return }
        session?.document.released()
        session?.document.commitText()
        isOpen = false
        host?.closeEditor()
    }

    func copy() async throws {
        try Task.checkCancellation()
        guard enabled else { throw Failure.disabled }
        guard isOpen, let session else { throw Failure.noImage }
        session.document.released()
        session.document.commitText()
        let marks = session.document.marks
        let identity = UUID()
        let clipboardCount = pasteboard.changeCount
        operation = identity
        defer { if operation == identity { operation = nil } }
        let png = try await render(session.image, marks)
        try Task.checkCancellation()
        guard enabled, isOpen, operation == identity, self.session?.document === session.document,
              session.document.marks == marks, session.document.textEdit == nil,
              pasteboard.changeCount == clipboardCount else { throw CancellationError() }
        let item = NSPasteboardItem()
        guard item.setData(png, forType: .png) else { throw Failure.clipboard }
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { throw Failure.clipboard }
        close()
        self.session = nil
    }

    func handle(_ event: NSEvent) -> Bool {
        guard enabled, isOpen, let document else { return false }
        if document.textEdit != nil {
            guard event.keyCode == 53 else { return false }
            document.cancelText()
            return true
        }
        let flags = event.modifierFlags
        var modifiers: CaptureEditorKeyAction.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        guard let action = CaptureEditorKeyAction.action(keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers, modifiers: modifiers) else { return false }
        switch action {
        case .copy:
            requestCopy()
        case .close: close()
        default: document.apply(action)
        }
        return true
    }

    func requestCopy() {
        copyTask?.cancel()
        copyFailure = nil
        copyTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await copy()
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                reportRenderFailure(error)
            }
        }
    }

    func reportRenderFailure(_ error: any Error) {
        copyFailure = error
        reportFailure?(error)
    }

    func reportPreviewFailure(_ error: any Error) {
        guard !previewFailing else { return }
        previewFailing = true
        reportRenderFailure(error)
    }

    func previewSucceeded() { previewFailing = false }

    private func makeSession(image: CaptureEditorImage, source: NSImage?, clipboardCount: Int?) -> Session {
        Session(document: CaptureEditorDocument(size: image.points, markScale: image.markScale,
            textSize: { CaptureEditorRender.textSize($0, markScale: image.markScale) }),
            image: image, source: source, clipboardCount: clipboardCount)
    }

    private func present(_ session: Session) {
        previewFailing = false
        copyTask?.cancel()
        copyTask = nil
        operation = nil
        self.session = session
        isOpen = true
        host?.openEditor(session.document, image: session.image)
    }
}
