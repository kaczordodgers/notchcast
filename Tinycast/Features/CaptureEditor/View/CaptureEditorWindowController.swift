import AppKit
import SwiftUI

@MainActor
final class CaptureEditorWindowController: CaptureEditorCoordinator.Host {
    static let shared = CaptureEditorWindowController()
    weak var coordinator: CaptureEditorCoordinator?
    private(set) var window: NSPanel?

    func attach(to coordinator: CaptureEditorCoordinator) {
        self.coordinator = coordinator
        coordinator.host = self
    }

    func openEditor(_ document: CaptureEditorDocument, image: CaptureEditorImage) {
        guard let coordinator else { return }
        let panel = CaptureEditorPanel(contentRect: CGRect(origin: .zero,
            size: CGSize(width: Theme.Size.panelWidth, height: Theme.Size.panelHeight)),
            styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        panel.coordinator = coordinator
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.isMovableByWindowBackground = false
        panel.followMotion()
        panel.contentView = NSHostingView(rootView: CaptureEditorView(document: document,
            image: image, coordinator: coordinator).motionScope())
        window?.orderOut(nil)
        window = panel
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func closeEditor() {
        window?.orderOut(nil)
        window = nil
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
