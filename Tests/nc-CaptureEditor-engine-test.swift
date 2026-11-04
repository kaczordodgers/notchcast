// notchcast-sources: Tinycast/Features/CaptureEditor/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/Service/CaptureEditorRender.swift
// notchcast-sources: Tinycast/Features/CaptureEditor/Service/CaptureEditorModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
import CoreGraphics
import Foundation

@main
struct CaptureEditorTest {
    @MainActor
    static func main() async throws {
        let context = CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8,
                                bytesPerRow: 384, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 48, width: 48, height: 48))
        let image = context.makeImage()!
        var document = CaptureEditorDocument(image: image)
        let box = CGRect(x: 8, y: 8, width: 64, height: 64)
        for tool in CaptureEditorDocument.Tool.allCases {
            document.pick(tool)
            let id = document.add(frame: box, text: "Test")!
            document.select(id)
            document.moveSelected(by: CGSize(width: 2, height: 3))
            precondition(document.annotations.last!.frame.minX == 10)
            document.undo()
            precondition(document.annotations.last!.frame == box)
            document.resizeSelected(to: CGRect(x: 1, y: 1, width: 30, height: 30))
            document.undo()
            let result = try CaptureEditorRender.flatten(document)
            precondition(result.width == 96 && result.height == 96)
            precondition(result.dataProvider!.data! as Data != image.dataProvider!.data! as Data)
            let pixels = result.dataProvider!.data! as Data
            let colors = stride(from: 0, to: pixels.count - 3, by: 4).map {
                Array(pixels[$0..<($0 + 4)])
            }
            if tool == .blur {
                precondition(colors.contains { $0[0] > 0 && $0[0] < 255 && $0[0] == $0[1] })
                precondition(colors[95] == [255, 255, 255, 255])
            } else {
                precondition(colors.contains { $0[0] > 200 && $0[1] < 50 && $0[2] < 50 })
            }
            document.undo()
            precondition(document.annotations.isEmpty)
        }
        precondition(document.add(frame: .zero) == nil)
        let suite = "capture-editor-test-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        let module = CaptureEditorModule()
        let controller = NotchcastModuleController([
            .init(requires: [.captureEditor], module: module),
        ], preferences: preferences)
        preferences.set(.captureEditor, false)
        controller.run()
        precondition(!module.isRunning)
        preferences.set(.captureEditor, true)
        controller.run()
        precondition(module.isRunning)
        try module.open(image)
        var copied = false
        try await module.copy { result in copied = result.width == 96 }
        precondition(copied)
        preferences.set(.captureEditor, false)
        controller.run()
        precondition(!module.isRunning && module.document == nil)
        do {
            try module.open(image)
            fatalError("Disabled module opened")
        } catch CaptureEditorModule.Failure.disabled {}
        print("CaptureEditor model, bitmap render, injected copy and switch lifecycle PASSED")
    }
}
