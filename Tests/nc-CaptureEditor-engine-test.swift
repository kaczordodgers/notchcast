// notchcast-sources: Tinycast/Features/CaptureEditor/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift

import AppKit
import ImageIO

@main
struct CaptureEditorEngineTest {
    @MainActor
    final class Host: CaptureEditorCoordinator.Host {
        var opened: [CaptureEditorDocument] = []
        var closed = 0
        func openEditor(_ document: CaptureEditorDocument, image: CaptureEditorImage) { opened.append(document) }
        func closeEditor() { closed += 1 }
    }

    @MainActor
    final class RenderGate {
        var continuation: CheckedContinuation<Data, Never>?
        func render() async -> Data {
            await withCheckedContinuation { continuation = $0 }
        }
        func finish(_ data: Data) {
            continuation?.resume(returning: data)
            continuation = nil
        }
    }

    @MainActor
    static func main() async throws {
        toolsAndHistory()
        keys()
        try await rendering()
        try await sessions()
        try await staleCopies()
        try await keyboardCopies()
        let released = CaptureEditorCoordinator()
        released.start()
        weak var retained: NSImage?
        do {
            let source = image()
            let temporary = NSImage(cgImage: source.pixels, size: source.points)
            retained = temporary
            try released.open(image: temporary)
        }
        precondition(retained != nil)
        released.close()
        precondition(retained == nil && released.document == nil)
        print("PASS: capture editor tools, selection/move/resize, text, undo/redo, keys, full-res PNG/pixelate, sources, switch")
    }

    @MainActor
    static func document() -> CaptureEditorDocument {
        CaptureEditorDocument(size: CGSize(width: 100, height: 80), textSize: {
            CaptureEditorRender.textSize($0, markScale: 1)
        })
    }

    @MainActor
    static func draw(_ document: CaptureEditorDocument, _ tool: CaptureEditorTool,
                     from: CGPoint = CGPoint(x: 10, y: 10), to: CGPoint = CGPoint(x: 60, y: 50)) {
        document.pick(tool)
        document.pressed(at: from, slack: 1)
        document.dragged(to: to)
        document.released()
    }

    @MainActor
    static func toolsAndHistory() {
        let from = CGPoint(x: 10, y: 10), to = CGPoint(x: 60, y: 50)
        let flat = CaptureEditorMark(shape: .ellipse(CGRect(x: 10, y: 20, width: 40, height: 0)), color: .red)
        precondition(flat.hits(CGPoint(x: 30, y: 21), slack: 8, markScale: 1, textSize: { _ in .zero }))
        precondition(!flat.hits(CGPoint(x: 30, y: 40), slack: 8, markScale: 1, textSize: { _ in .zero }))
        for tool in CaptureEditorTool.allCases {
            let doc = document()
            draw(doc, tool)
            if tool == .text {
                precondition(doc.marks.isEmpty && doc.textEdit?.origin == from)
                doc.textEdit?.string = "  Label\nsecond line  "
                doc.commitText()
            }
            let expected: CaptureEditorMark.Shape
            switch tool {
            case .arrow: expected = .arrow(from: from, to: to)
            case .text: expected = .text(origin: from, string: "Label\nsecond line")
            case .rectangle: expected = .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40))
            case .ellipse: expected = .ellipse(CGRect(x: 10, y: 10, width: 50, height: 40))
            case .blur: expected = .blur(CGRect(x: 10, y: 10, width: 50, height: 40))
            }
            precondition(doc.marks.count == 1 && doc.marks[0].shape == expected && doc.canUndo)
            let original = doc.marks
            doc.released()
            doc.undo()
            precondition(doc.marks.isEmpty && !doc.canUndo && doc.canRedo)
            doc.redo()
            precondition(doc.marks == original && !doc.canRedo)
            doc.pick(.arrow)
            let hit = tool == .ellipse ? CGPoint(x: 35, y: 10) : CGPoint(x: 20, y: 18)
            let pick = tool == .rectangle ? CGPoint(x: 10, y: 30) : hit
            doc.pressed(at: pick, slack: 2)
            doc.dragged(to: CGPoint(x: pick.x + 5, y: pick.y + 7))
            doc.released()
            precondition(doc.marks == original.map { $0.moved(by: CGSize(width: 5, height: 7)) })
            doc.undo()
            precondition(doc.marks == original)
            if tool != .text {
                let handle = doc.marks[0].handles.last!
                let resized = CGPoint(x: 75, y: 65)
                doc.pressed(at: handle.point, slack: 1)
                doc.dragged(to: resized)
                doc.released()
                precondition(doc.marks[0] == original[0].resized(handle.handle, to: resized))
                doc.undo()
                precondition(doc.marks == original)
            }
            doc.pick(.blue)
            precondition(doc.marks[0].color == .blue && !doc.canRedo)
            doc.undo()
            precondition(doc.marks == original)
            doc.deleteSelected()
            precondition(doc.marks.isEmpty && doc.selection == nil)
            doc.undo()
            precondition(doc.marks == original)
        }
        let doc = document()
        draw(doc, .arrow, to: CGPoint(x: 11, y: 11))
        precondition(doc.marks.isEmpty && !doc.canUndo)
        draw(doc, .rectangle, from: to, to: from)
        precondition(doc.marks[0].shape == .rectangle(CGRect(x: 10, y: 10, width: 50, height: 40)))
        doc.pressed(at: CGPoint(x: 35, y: 30), slack: 1)
        doc.dragged(to: CGPoint(x: 45, y: 40))
        doc.released()
        precondition(doc.marks.count == 2)
        let text = document()
        draw(text, .text)
        text.textEdit?.string = "First"
        text.commitText()
        text.pressed(at: CGPoint(x: 15, y: 15), slack: 1)
        text.textEdit?.string = "Second"
        text.commitText()
        precondition(text.marks.count == 1 && text.marks[0].shape == .text(origin: from, string: "Second"))
        text.undo()
        precondition(text.marks[0].shape == .text(origin: from, string: "First"))
        text.pressed(at: CGPoint(x: 15, y: 15), slack: 1)
        text.textEdit?.string = ""
        text.commitText()
        precondition(text.marks.isEmpty && !text.canRedo)
        text.undo()
        text.pressed(at: CGPoint(x: 15, y: 15), slack: 1)
        text.textEdit?.string = "Cancelled"
        text.cancelText()
        precondition(text.marks[0].shape == .text(origin: from, string: "First"))
    }

    static func keys() {
        for tool in CaptureEditorTool.allCases {
            let action = CaptureEditorKeyAction.action(keyCode: 0, characters: tool.key.uppercased(), modifiers: [])
            precondition(action == .tool(tool))
            precondition(CaptureEditorKeyAction.action(keyCode: 0, characters: tool.key, modifiers: .option) == nil)
        }
        for code in [UInt16(36), 76] {
            precondition(CaptureEditorKeyAction.action(keyCode: code, characters: nil, modifiers: []) == .copy)
        }
        for code in [UInt16(51), 117] {
            precondition(CaptureEditorKeyAction.action(keyCode: code, characters: nil, modifiers: []) == .delete)
        }
        precondition(CaptureEditorKeyAction.action(keyCode: 53, characters: nil, modifiers: []) == .close)
        precondition(CaptureEditorKeyAction.action(keyCode: 8, characters: "c", modifiers: .command) == .copy)
        precondition(CaptureEditorKeyAction.action(keyCode: 6, characters: "z", modifiers: .command) == .undo)
        precondition(CaptureEditorKeyAction.action(keyCode: 6, characters: "Z", modifiers: [.command, .shift]) == .redo)
        precondition(CaptureEditorKeyAction.action(keyCode: 6, characters: "z", modifiers: [.command, .control]) == nil)
        precondition(CaptureEditorKeyAction.action(keyCode: 0, characters: "q", modifiers: []) == nil)
    }

    static func image(space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) -> CaptureEditorImage {
        var bytes = [UInt8](repeating: 255, count: 200 * 160 * 4)
        for y in 0..<160 {
            for x in 0..<200 {
                let offset = (y * 200 + x) * 4
                bytes[offset] = UInt8((x * 23 + y * 7) % 256)
                bytes[offset + 1] = UInt8((x * 3 + y * 19) % 256)
                bytes[offset + 2] = UInt8((x * 13 + y * 11) % 256)
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let pixels = CGImage(width: 200, height: 160, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 800,
            space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return CaptureEditorImage(pixels: pixels, points: CGSize(width: 100, height: 80))!
    }

    static func bytes(_ image: CGImage) -> Data {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: context.data!, count: image.width * image.height * 4)
    }

    @MainActor
    static func rendering() async throws {
        let source = image()
        let p3 = image(space: CGColorSpace(name: CGColorSpace.displayP3)!)
        let p3Flat = try CaptureEditorRender.flatten(p3, marks: [])
        precondition(p3Flat.colorSpace?.name == CGColorSpace.displayP3)
        let baseline = try CaptureEditorRender.flatten(source, marks: [])
        let region = CGRect(x: 10, y: 10, width: 40, height: 30)
        let flat = try CaptureEditorRender.flatten(source, marks: [.init(shape: .blur(region))])
        precondition(flat.width == 200 && flat.height == 160)
        precondition(bytes(baseline) == bytes(source.pixels))
        let inside = CGRect(x: 20, y: 20, width: 80, height: 60)
        precondition(bytes(flat.cropping(to: inside)!) != bytes(baseline.cropping(to: inside)!))
        let cell = Array(bytes(flat.cropping(to: CGRect(x: 22, y: 22, width: 4, height: 4))!))
        precondition(stride(from: 0, to: cell.count, by: 4).allSatisfy { Array(cell[$0..<$0 + 4]) == Array(cell[0..<4]) })
        let outside = CGRect(x: 110, y: 0, width: 90, height: 160)
        precondition(bytes(flat.cropping(to: outside)!) == bytes(baseline.cropping(to: outside)!))
        for tool in CaptureEditorTool.allCases {
            let doc = document()
            draw(doc, tool)
            if tool == .text { doc.textEdit?.string = "Visible text"; doc.commitText() }
            let result = try CaptureEditorRender.flatten(source, marks: doc.marks)
            precondition(bytes(result) != bytes(baseline))
        }
        let png = try await CaptureEditorRender.png(source, marks: [.init(shape: .blur(region))])
        let decoded = CGImageSourceCreateWithData(png as CFData, nil)!
        let decodedImage = CGImageSourceCreateImageAtIndex(decoded, 0, nil)!
        precondition(decodedImage.width == 200 && decodedImage.height == 160)
        let properties = CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil)! as NSDictionary
        precondition(abs((properties[kCGImagePropertyDPIWidth] as? Double ?? 0) - 144) < 0.1)
        precondition(CaptureEditorImage(pixels: source.pixels, points: .zero) == nil)
        precondition(CaptureEditorImage(pixels: source.pixels, points: CGSize(width: CGFloat.infinity, height: 1)) == nil)
    }

    @MainActor
    static func sessions() async throws {
        let board = NSPasteboard(name: .init("capture-editor-test-\(UUID())"))
        defer { board.releaseGlobally() }
        let host = Host()
        let editor = CaptureEditorCoordinator(pasteboard: board, host: host,
            reportFailure: { _ in preconditionFailure("Unexpected copy failure") })
        let suite = "capture-editor-preferences-\(UUID())"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        precondition(!NotchcastFeature.captureEditor.defaultEnabled && NotchcastFeature.captureEditor.isWired)
        precondition(NotchcastFeature.captureEditor.settingsGroup == .captureAndDictation)
        precondition(!preferences.isOn(.captureEditor))
        let controller = NotchcastModuleController([.init(requires: [.captureEditor], module: editor)], preferences: preferences)
        controller.run()
        do {
            try editor.openFromClipboardOrLast()
            preconditionFailure("disabled")
        } catch CaptureEditorCoordinator.Failure.disabled {}
        preferences.set(.captureEditor, true)
        for _ in 0..<1000 where !editor.enabled { await Task.yield() }
        precondition(editor.enabled)
        do {
            try editor.openFromClipboardOrLast()
            preconditionFailure("empty sources")
        } catch CaptureEditorCoordinator.Failure.noImage {
            precondition(CaptureEditorCoordinator.Failure.noImage.errorDescription == "No Image to Edit")
        }
        let source = image()
        let last = NSImage(cgImage: source.pixels, size: source.points)
        editor.lastCapture = last
        try editor.openFromClipboardOrLast()
        let first = editor.document!
        draw(first, .rectangle)
        try await handle(editor, event("z", code: 6, modifiers: .command))
        precondition(first.marks.isEmpty)
        try await handle(editor, event("Z", code: 6, modifiers: [.command, .shift]))
        precondition(first.marks.count == 1)
        first.pressed(at: CGPoint(x: 10, y: 30), slack: 1)
        first.released()
        try await handle(editor, event("", code: 51))
        precondition(first.marks.isEmpty)
        first.undo()
        try await handle(editor, event("t", code: 17, modifiers: .capsLock))
        first.pressed(at: CGPoint(x: 75, y: 60), slack: 1)
        first.textEdit?.string = "Cancelled by escape"
        try await handle(editor, event("a", code: 0), expected: false)
        try await handle(editor, event("", code: 53))
        precondition(first.textEdit == nil && editor.isOpen)
        try await handle(editor, event("", code: 53))
        precondition(!editor.isOpen)
        editor.close()
        try editor.open(image: last)
        precondition(editor.document !== first && editor.document?.marks.isEmpty == true)
        let clipboard = NSImage(cgImage: source.pixels, size: CGSize(width: 50, height: 40))
        precondition(board.writeObjects([clipboard]))
        try editor.openFromClipboardOrLast()
        precondition(editor.document !== first && editor.document?.size == CGSize(width: 50, height: 40))
        let clipboardDocument = editor.document!
        draw(clipboardDocument, .arrow)
        editor.close()
        try editor.openFromClipboardOrLast()
        precondition(editor.document !== clipboardDocument && editor.document?.marks.isEmpty == true)
        board.clearContents()
        precondition(board.writeObjects([clipboard]))
        try editor.openFromClipboardOrLast()
        precondition(editor.document !== clipboardDocument && editor.document?.marks.isEmpty == true)
        board.clearContents()
        try editor.openFromClipboardOrLast()
        precondition(editor.document?.size == source.points)
        editor.lastCapture = NSImage(cgImage: source.pixels, size: source.points)
        precondition(!editor.isOpen && editor.document == nil)
        try editor.openFromClipboardOrLast()
        precondition(editor.document?.marks.isEmpty == true)
        draw(editor.document!, .text)
        editor.document?.textEdit?.string = "Copy commits text"
        try await editor.copy()
        precondition(!editor.isOpen && editor.document == nil)
        let copied = board.data(forType: .png)!
        let decoded = CGImageSourceCreateWithData(copied as CFData, nil)!
        precondition(CGImageSourceCreateImageAtIndex(decoded, 0, nil)!.width == 200)
        try editor.openFromClipboardOrLast()
        preferences.set(.captureEditor, false)
        for _ in 0..<1000 where editor.enabled { await Task.yield() }
        precondition(!editor.enabled && !editor.isOpen && host.closed > 0)
        do {
            try await editor.copy()
            preconditionFailure("disabled copy")
        } catch CaptureEditorCoordinator.Failure.disabled {}
    }

    @MainActor
    static func handle(_ editor: CaptureEditorCoordinator, _ event: NSEvent, expected: Bool = true) async throws {
        let handled: Bool = editor.handle(event)
        precondition(handled == expected)
    }

    @MainActor
    static func event(_ characters: String, code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                        isARepeat: false, keyCode: code)!
    }

    @MainActor
    static func staleCopies() async throws {
        let board = NSPasteboard(name: .init("capture-editor-stale-\(UUID())"))
        defer { board.releaseGlobally() }
        let source = image()
        let image = NSImage(cgImage: source.pixels, size: source.points)
        for mutation in 0..<5 {
            let gate = RenderGate()
            let editor = CaptureEditorCoordinator(pasteboard: board, render: { _, _ in await gate.render() },
                reportFailure: { _ in preconditionFailure("Unexpected copy failure") })
            editor.start()
            try editor.open(image: image)
            let task = Task { try await editor.copy() }
            for _ in 0..<1000 where gate.continuation == nil { await Task.yield() }
            precondition(gate.continuation != nil)
            switch mutation {
            case 0: editor.stop()
            case 1: editor.lastCapture = NSImage(cgImage: source.pixels, size: source.points)
            case 2: draw(editor.document!, .arrow)
            case 3: task.cancel()
            default:
                board.clearContents()
                precondition(board.setString("Keep this", forType: .string))
            }
            let count = board.changeCount
            gate.finish(Data([1, 2, 3]))
            do {
                try await task.value
                preconditionFailure("stale copy")
            } catch is CancellationError {}
            precondition(board.changeCount == count)
        }
    }

    @MainActor
    static func keyboardCopies() async throws {
        let board = NSPasteboard(name: .init("capture-editor-keys-\(UUID())"))
        defer { board.releaseGlobally() }
        let source = image()
        let image = NSImage(cgImage: source.pixels, size: source.points)
        let gate = RenderGate()
        var failures = 0
        let editor = CaptureEditorCoordinator(pasteboard: board, render: { _, _ in await gate.render() },
            reportFailure: { _ in failures += 1 })
        precondition(!editor.handle(event("a", code: 0)))
        editor.start()
        try editor.open(image: image)
        precondition(!editor.handle(event("q", code: 12)))
        precondition(editor.handle(event("r", code: 15)))
        precondition(editor.handle(event("c", code: 8, modifiers: .command)))
        precondition(editor.isOpen && board.data(forType: .png) == nil)
        for _ in 0..<1000 where gate.continuation == nil { await Task.yield() }
        precondition(gate.continuation != nil)
        let png = try await CaptureEditorRender.png(source, marks: [])
        gate.finish(png)
        for _ in 0..<1000 where editor.isOpen { await Task.yield() }
        precondition(!editor.isOpen && board.data(forType: .png) == png && failures == 0)
        let failing = CaptureEditorCoordinator(pasteboard: board,
            render: { _, _ in throw CaptureEditorRender.Failure.encoding }, reportFailure: { _ in failures += 1 })
        failing.start()
        try failing.open(image: image)
        precondition(failing.handle(event("", code: 36)))
        for _ in 0..<1000 where failures == 0 { await Task.yield() }
        precondition(failures == 1 && failing.isOpen)
        failing.stop()
    }
}
