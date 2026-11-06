import AppKit
import SwiftUI

@MainActor
final class CaptureEditorWindowController: CaptureEditorCoordinator.Host {
    static let shared = CaptureEditorWindowController()
    weak var coordinator: CaptureEditorCoordinator?
    private(set) var window: NSPanel?
    var pointerLocation: () -> CGPoint = { NSEvent.mouseLocation }

    func attach(to coordinator: CaptureEditorCoordinator) {
        self.coordinator = coordinator
        coordinator.host = self
    }

    func openEditor(_ document: CaptureEditorDocument, image: CaptureEditorImage) {
        guard let coordinator else { return }
        let panel = CaptureEditorPanel(contentRect: CGRect(origin: .zero,
            size: CGSize(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight)),
            styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.coordinator = coordinator
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.followMotion()
        panel.contentView = NSHostingView(rootView: CaptureEditorView(document: document,
            image: image, coordinator: coordinator).motionScope())
        closeEditor()
        window = panel
        place(panel)
        panel.makeKeyAndOrderFront(nil)
    }

    func closeEditor() {
        window?.orderOut(nil)
        // An ordered-out panel still renders the reused document and its text field steals focus.
        window?.contentView = nil
        window = nil
    }

    private func place(_ panel: NSPanel) {
        let pointer = pointerLocation()
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else {
            return panel.center()
        }
        let area = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: area.midX - panel.frame.width / 2, y: area.midY - panel.frame.height / 2))
    }
}

final class CaptureEditorPanel: NSPanel, AnimatedPanel {
    weak var coordinator: CaptureEditorCoordinator?
    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, coordinator?.handle(event) == true { return }
        super.sendEvent(event)
    }
}
