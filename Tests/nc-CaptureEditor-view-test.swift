// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/CaptureEditor/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/Service/*.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/View/*.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/CaptureEditorCoordinator+Registration.swift
// notchcast-kit: core host
// notchcast-sources: Tinycast/DesignSystem/Interaction/AnimatedPanel.swift
// notchcast-sources: Tinycast/DesignSystem/Interaction/Motion.swift
// notchcast-sources: Tinycast/DesignSystem/Theme.swift Tinycast/DesignSystem/InterfaceMetrics.swift
// notchcast-sources: Tinycast/DesignSystem/BarButton.swift Tinycast/DesignSystem/ModalActionButtonStyle.swift
// notchcast-sources: Tinycast/DesignSystem/SymbolImage.swift Tinycast/DesignSystem/GlassEffectView.swift
// notchcast-sources: Tinycast/Features/Appearance/Model/*.swift Tinycast/Features/Appearance/Service/*.swift
// notchcast-sources: Tinycast/Platform/Appearance.swift

import AppKit
import SwiftUI
import ImageIO

enum DialogTone { case danger }

enum SystemSymbolName {
    static func resolve(_ name: String, isDark: Bool) -> String { name }
}

enum PopoverMenuIcon {
    case symbol(String), asset(String), file(path: String), thumbnail(id: UUID, data: Data), blank
}

struct MenuFileIcon: View {
    let path: String
    var body: some View { EmptyView() }
}

struct MenuThumbnail: View {
    let id: UUID
    let data: Data
    var body: some View { EmptyView() }
}

@main struct CaptureEditorViewTest {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let host = CaptureEditorWindowController()
        let coordinator = CaptureEditorCoordinator(pasteboard: board)
        var failures = 0
        let preview = CaptureEditorCoordinator(pasteboard: board, reportFailure: { _ in failures += 1 })
        preview.reportPreviewFailure(CaptureEditorRender.Failure.encoding)
        preview.reportPreviewFailure(CaptureEditorRender.Failure.encoding)
        precondition(failures == 1)
        preview.previewSucceeded()
        preview.reportPreviewFailure(CaptureEditorRender.Failure.encoding)
        precondition(failures == 2)
        let entries = CaptureEditorCoordinator.register()
        precondition(entries.count == 1 && entries[0].requires == [.captureEditor] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === CaptureEditorCoordinator.shared)
        precondition(CaptureEditorWindowController.shared.coordinator === CaptureEditorCoordinator.shared)
        var dangers = 0
        NotchcastHost.current.showMessage = { _, tone in if tone == .danger { dangers += 1 } }
        CaptureEditorCoordinator.shared.reportPreviewFailure(CaptureEditorRender.Failure.encoding)
        precondition(dangers == 1)
        print("PASS: registration attaches the shared window host, one entry, failures reach the host seam")
        host.attach(to: coordinator)
        coordinator.start()
        let context = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 200))
        let source = NSImage(cgImage: context.makeImage()!, size: CGSize(width: 320, height: 200))
        try coordinator.open(image: source)
        precondition(host.window?.isVisible == true && coordinator.isOpen)
        let viewSource = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tinycast/Features/CaptureEditor/View/CaptureEditorView.swift")
        let viewCode = try String(contentsOf: viewSource, encoding: .utf8)
        precondition(!viewCode.contains("CaptureEditorRender.png") && !viewCode.contains("CaptureEditorRender.flatten"))
        print("PASS: view has no flatten or PNG call")
        let document = coordinator.document!
        document.pressed(at: CGPoint(x: 20, y: 40), slack: 2)
        document.dragged(to: CGPoint(x: 180, y: 40))
        document.released()
        preview.reportPreviewFailure(CaptureEditorRender.Failure.encoding)
        precondition(failures == 2)
        preview.start()
        try preview.open(image: source)
        preview.reportPreviewFailure(CaptureEditorRender.Failure.encoding)
        precondition(failures == 3)
        document.pick(.text)
        document.pressed(at: CGPoint(x: 30, y: 100), slack: 2)
        document.textEdit?.string = "OK"
        document.commitText()
        try await coordinator.copy()
        let png = board.data(forType: .png)!
        let decoded = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(png as CFData, nil)!, 0, nil)!
        precondition(decoded.width == 320 && decoded.height == 200)
        let bitmap = NSBitmapImageRep(cgImage: decoded)
        let pixel = bitmap.colorAt(x: 80, y: 40)!.usingColorSpace(.deviceRGB)!
        precondition(pixel.redComponent > 0.5)
        precondition(!coordinator.isOpen && host.window == nil)
        try coordinator.openCapture(url: nil, clipboard: true)
        precondition(host.window?.isVisible == true)
        coordinator.close()
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("capture.png")
        try png.write(to: file)
        board.clearContents()
        precondition(board.writeObjects([NSImage(size: CGSize(width: 16, height: 16))]))
        try coordinator.openCapture(url: file, clipboard: true)
        precondition(coordinator.document?.size == CGSize(width: 320, height: 200))
        precondition(host.window?.isVisible == true)
        coordinator.close()
        precondition(coordinator.document != nil)
        try coordinator.open(image: source)
        let panel = host.window!
        panel.sendEvent(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        precondition(!coordinator.isOpen && host.window == nil)
        try typeText(coordinator: coordinator, host: host, source: source)
        try placement(coordinator: coordinator, host: host, source: source)
        coordinator.stop()
        print("PASS: Host window opens/closes; arrow + OK Copy PNG 320x200 with red arrow pixel; Esc closes")
    }

    @MainActor static func settle() {
        RunLoop.main.run(until: .now.addingTimeInterval(0.2))
    }

    @MainActor static func typeText(coordinator: CaptureEditorCoordinator, host: CaptureEditorWindowController,
                                    source: NSImage) throws {
        try coordinator.open(image: source)
        let panel = host.window!
        let document = coordinator.document!
        document.pick(.text)
        precondition(panel.styleMask.contains(.nonactivatingPanel))
        panel.makeKeyAndOrderFront(nil)
        settle()
        precondition(panel.isKeyWindow)
        let point = CGPoint(x: 300, y: panel.frame.height - 200)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            panel.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!)
            settle()
        }
        precondition(document.textEdit != nil, "Text-tool click opened no text edit")
        for (characters, keyCode) in [("O", UInt16(31)), ("K", 40), ("\r", 36)] {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                panel.sendEvent(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber, context: nil,
                    characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                    keyCode: keyCode)!)
            }
            settle()
        }
        let typed = document.marks.contains {
            if case .text(_, "OK") = $0.shape { true } else { false }
        }
        precondition(document.textEdit == nil && typed,
            "typed text not committed: edit=\(String(describing: document.textEdit)) "
                + "responder=\(String(describing: panel.firstResponder))")
        coordinator.close()
        print("PASS: reopened editor takes a Text-tool click, typed OK + Return commits a text mark")
    }

    @MainActor static func placement(coordinator: CaptureEditorCoordinator, host: CaptureEditorWindowController,
                                     source: NSImage) throws {
        for screen in NSScreen.screens {
            host.pointerLocation = { CGPoint(x: screen.frame.midX, y: screen.frame.midY) }
            try coordinator.open(image: source)
            let frame = host.window!.frame
            precondition(screen.frame.contains(frame), "panel \(frame) outside screen \(screen.frame)")
            precondition(abs(frame.midX - screen.visibleFrame.midX) < 1 && abs(frame.midY - screen.visibleFrame.midY) < 1)
            coordinator.close()
        }
        host.pointerLocation = { CGPoint(x: -100_000, y: -100_000) }
        try coordinator.open(image: source)
        precondition(NSScreen.main!.frame.contains(host.window!.frame))
        coordinator.close()
        print("PASS: editor centres on the pointer's screen across \(NSScreen.screens.count) screens; off-screen uses main")
    }
}
