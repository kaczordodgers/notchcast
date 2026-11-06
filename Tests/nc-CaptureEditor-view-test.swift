// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/CaptureEditor/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/Service/*.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/View/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
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
        _ = NSApplication.shared
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
        let document = coordinator.document!
        document.pressed(at: CGPoint(x: 20, y: 40), slack: 2)
        document.dragged(to: CGPoint(x: 180, y: 40))
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for offset in 0..<20 {
                document.dragged(to: CGPoint(x: 180 + offset, y: 40))
                let content = host.window!.contentView!
                content.layoutSubtreeIfNeeded()
                let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                content.cacheDisplay(in: content.bounds, to: bitmap)
            }
        }
        print("PASS: 20 live overlay drag redraws in \(elapsed); view has no flatten or PNG call")
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
        if let folder = ProcessInfo.processInfo.environment["CAPTURE_EDITOR_SNAPSHOTS"] {
            let panel = host.window!
            let screen = NSScreen.screens.first {
                let id = ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
                return CGDisplayVendorNumber(id) == 0x0D17
            }!
            panel.setFrameOrigin(screen.visibleFrame.origin)
            for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
                panel.appearance = NSAppearance(named: appearance)
                try await Task.sleep(for: .milliseconds(500))
                let content = panel.contentView!
                content.layoutSubtreeIfNeeded()
                let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(
                    to: URL(filePath: folder).appendingPathComponent("capture-editor-\(name).png"))
            }
        }
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
        coordinator.stop()
        print("PASS: Host window opens/closes; arrow + OK Copy PNG 320x200 with red arrow pixel; Esc closes")
    }
}
