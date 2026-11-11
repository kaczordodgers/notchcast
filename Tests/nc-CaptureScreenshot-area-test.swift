// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-kit: core host
// notchcast-sources: Tinycast/Features/CaptureScreenshot/ScreenshotModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastIdentity.swift
// notchcast-sources: Tinycast/Platform/AppPaths.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/ScreenshotModule+Command.swift
// notchcast-sources: Tinycast/Features/CaptureScreenshot/Model/ScreenshotRequest.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/*.swift
// notchcast-sources: Tinycast/Platform/ScreenTarget.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/Service/*.swift
import AppKit

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature?
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

extension ScreenshotModule {
    static var instance: ScreenshotModule?
    static var shared: ScreenshotModule { instance! }
}

enum DialogTone { case danger }

@MainActor enum ScreenshotService {
    static func capture(
        _ request: ScreenshotRequest, destination: ScreenshotRequest.Destination,
        isEnabled: @MainActor () -> Bool
    ) async throws -> URL? { preconditionFailure("Harness must inject capture") }
}

@main struct CaptureScreenshotAreaTest {
    @MainActor static func main() async throws {
        var messages: [String] = []
        NotchcastHost.current.showMessage = { text, _ in messages.append(text) }
        let suite = "screenshot-area-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var starts = 0
        var next: CaptureAreaSelection?
        let area = CaptureAreaService(hasScreenRecordingAccess: { true }, select: {
            starts += 1
            $0(next)
        })
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let editor = CaptureEditorCoordinator(pasteboard: board)
        editor.start()
        let openInEditor: (URL?, Bool) throws -> Void = { try editor.openCapture(url: $0, clipboard: $1) }
        board.setString("Untouched", forType: .string)
        var captures: [CGRect] = []
        var files = 0
        let module = ScreenshotModule(defaults: defaults, area: area, capture: { request, destination, valid in
            precondition(valid())
            guard case .rect(let rect) = request else { preconditionFailure("Expected rect") }
            captures.append(rect)
            switch destination {
            case .clipboard: board.clearContents(); board.setString("Captured", forType: .string)
            case .file: files += 1
            case .both: preconditionFailure("Unexpected destination")
            }
            return nil
        })
        module.openInEditor = openInEditor
        ScreenshotModule.instance = module
        defer { module.stop(); ScreenshotModule.instance = nil }
        let command = ScreenshotModule.areaCommand
        command.run()
        precondition(starts == 0)
        module.start()
        let wasOn = NotchcastPreferences.shared.isOn(.captureEditor)
        NotchcastPreferences.shared.set(.captureEditor, false)
        defer { NotchcastPreferences.shared.set(.captureEditor, wasOn) }
        for (frame, start, end, expected) in [
            (CGRect(x: 0, y: 0, width: 1440, height: 900), CGPoint(x: 10, y: 20),
             CGPoint(x: 110, y: 70), CGRect(x: 10, y: 830, width: 100, height: 50)),
            (CGRect(x: -1920, y: 200, width: 1920, height: 1080), CGPoint(x: -1800, y: 300),
             CGPoint(x: -1500, y: 500), CGRect(x: -1800, y: 400, width: 300, height: 200))
        ] {
            let selection = CaptureAreaSelection.make(from: start, to: end, displayID: 2,
                displayFrame: frame, mainDisplayHeight: 900)!
            precondition(selection.rect == expected)
            next = selection
            command.run()
            await module.commandTask?.value
            precondition(captures.last == expected)
        }
        precondition(starts == 2 && captures.count == 2)
        precondition(!editor.isOpen)
        NotchcastPreferences.shared.set(.captureEditor, true)
        command.run()
        await module.commandTask?.value
        precondition(!editor.isOpen)
        precondition(messages == [CaptureEditorCoordinator.Failure.noImage.localizedDescription])
        messages.removeAll()
        NotchcastPreferences.shared.set(.captureEditor, false)
        precondition(board.string(forType: .string) == "Captured")
        let changes = board.changeCount
        next = nil
        command.run()
        await module.commandTask?.value
        precondition(captures.count == 3 && board.changeCount == changes)
        module.destination = .file
        next = .init(rect: CGRect(x: 1, y: 2, width: 3, height: 4), displayID: 1, displayFrame: .zero)
        command.run()
        await module.commandTask?.value
        precondition(files == 1 && board.changeCount == changes)
        module.stop()
        command.run()
        precondition(captures.count == 4 && messages.isEmpty)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = NSImage(cgImage: context.makeImage()!, size: CGSize(width: 100, height: 80))
        let png = try await CaptureEditorRender.png(CaptureEditorImage(image)!, marks: [])
        let url = folder.appendingPathComponent("capture.png")
        try png.write(to: url)
        let flow = ScreenshotModule(defaults: defaults, area: area, capture: { _, destination, _ in
            if case .file = destination {} else {
                board.clearContents()
                precondition(board.writeObjects([image]))
            }
            if case .clipboard = destination { return nil }
            return url
        })
        flow.openInEditor = openInEditor
        flow.start()
        defer { flow.stop(); editor.stop() }
        NotchcastPreferences.shared.set(.captureEditor, true)
        for destination in ScreenshotModule.Destination.allCases {
            board.clearContents()
            flow.destination = destination
            flow.captureArea()
            await flow.commandTask?.value
            precondition(editor.isOpen)
            let document = editor.document!
            document.pick(.rectangle)
            document.pressed(at: CGPoint(x: 10, y: 10), slack: 1)
            document.dragged(to: CGPoint(x: 60, y: 50))
            document.released()
            let marks = document.marks
            precondition(marks.count == 1)
            editor.close()
            try editor.openFromClipboardOrLast()
            precondition(editor.document === document && editor.document?.marks == marks)
            print("PASS: captureArea → editor → close → Edit Capture retains marks for \(destination)")
            editor.close()
        }
        try FileManager.default.removeItem(at: folder)
        print("PASS: area command selection; primary and offset Quartz rects; cancel preserves clipboard; destination and stop")
    }
}
