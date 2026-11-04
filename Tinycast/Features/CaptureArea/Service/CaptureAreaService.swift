import AppKit

@MainActor
final class CaptureAreaService {
    enum Failure: Error { case screenRecordingDenied }

    private var windows: [NSWindow] = []
    private var completion: ((CaptureAreaSelection?) -> Void)?
    private let hasScreenRecordingAccess: () -> Bool
    private let requestScreenRecordingAccess: () -> Bool
    private let select: (((CaptureAreaSelection?) -> Void) -> Void)?

    init(
        hasScreenRecordingAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestScreenRecordingAccess: @escaping () -> Bool = { CGRequestScreenCaptureAccess() },
        select: (((CaptureAreaSelection?) -> Void) -> Void)? = nil
    ) {
        self.hasScreenRecordingAccess = hasScreenRecordingAccess
        self.requestScreenRecordingAccess = requestScreenRecordingAccess
        self.select = select
    }

    isolated deinit {
        for window in windows { window.close() }
    }

    func start(completion: @escaping (CaptureAreaSelection?) -> Void) throws {
        stop()
        guard hasScreenRecordingAccess() || requestScreenRecordingAccess() else {
            throw Failure.screenRecordingDenied
        }
        self.completion = completion
        if let select {
            select { [weak self] in self?.finish($0) }
            return
        }
        let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { continue }
            let window = OverlayWindow(
                contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.displayID = number.uint32Value
            view.displayFrame = screen.frame
            view.mainDisplayHeight = mainDisplayHeight
            view.finish = { [weak self] selection in self?.finish(selection) }
            window.contentView = view
            windows.append(window)
            window.orderFrontRegardless()
        }
        guard let window = windows.first else { finish(nil); return }
        NSApp.activate()
        window.makeKey()
        window.makeFirstResponder(window.contentView)
    }

    func stop() { finish(nil) }

    private func finish(_ selection: CaptureAreaSelection?) {
        let callback = completion
        completion = nil
        for window in windows { window.close() }
        windows.removeAll()
        callback?(selection)
    }

    private final class OverlayWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private final class SelectionView: NSView {
        var displayID: UInt32 = 0
        var displayFrame: CGRect = .zero
        var mainDisplayHeight: CGFloat = 0
        var finish: ((CaptureAreaSelection?) -> Void)?
        private var start: CGPoint?
        private var end: CGPoint?

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
        override func cancelOperation(_ sender: Any?) { finish?(nil) }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { finish?(nil) } else { super.keyDown(with: event) }
        }
        override func mouseDown(with event: NSEvent) {
            window?.makeKey()
            window?.makeFirstResponder(self)
            start = NSEvent.mouseLocation
            end = start
        }
        override func mouseDragged(with event: NSEvent) {
            end = NSEvent.mouseLocation
            needsDisplay = true
        }
        override func mouseUp(with event: NSEvent) {
            guard let start else { return }
            finish?(CaptureAreaSelection.make(
                from: start, to: NSEvent.mouseLocation,
                displayID: displayID, displayFrame: displayFrame, mainDisplayHeight: mainDisplayHeight))
        }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.black.withAlphaComponent(0.01).setFill()
            bounds.fill()
            guard let start, let end,
                let rect = CaptureAreaSelection.appKitRect(
                    from: start, to: end, displayFrame: displayFrame)
            else { return }
            NSColor.selectedControlColor.setStroke()
            NSBezierPath(rect: rect.offsetBy(
                dx: -displayFrame.minX, dy: -displayFrame.minY)).stroke()
        }
    }
}
