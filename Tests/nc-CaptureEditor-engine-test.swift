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
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 96))
        let blank = context.makeImage()!
        let directions: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 20, y: 20), CGPoint(x: 76, y: 76)),
            (CGPoint(x: 76, y: 76), CGPoint(x: 20, y: 20)),
            (CGPoint(x: 20, y: 76), CGPoint(x: 76, y: 20)),
            (CGPoint(x: 76, y: 20), CGPoint(x: 20, y: 76)),
            (CGPoint(x: 20, y: 48), CGPoint(x: 76, y: 48)),
            (CGPoint(x: 76, y: 48), CGPoint(x: 20, y: 48)),
            (CGPoint(x: 48, y: 20), CGPoint(x: 48, y: 76)),
            (CGPoint(x: 48, y: 76), CGPoint(x: 48, y: 20)),
        ]
        for (from, to) in directions {
            var arrowDocument = CaptureEditorDocument(image: blank)
            precondition(arrowDocument.arrow(from: from, to: to) != nil)
            let result = try CaptureEditorRender.flatten(arrowDocument)
            let pixels = result.dataProvider!.data! as Data
            let angle = atan2(to.y - from.y, to.x - from.x)
            func hasHead(at tip: CGPoint, angle: CGFloat) -> Bool {
                let x = Int((tip.x - 8 * cos(angle) - 3 * sin(angle)).rounded())
                let y = Int((tip.y - 8 * sin(angle) + 3 * cos(angle)).rounded())
                let offset = y * result.bytesPerRow + x * 4
                return pixels[offset] > 200 && pixels[offset + 1] < 50
            }
            precondition(hasHead(at: to, angle: angle))
            precondition(!hasHead(at: from, angle: angle + .pi))
            arrowDocument.moveSelected(by: CGSize(width: 2, height: 3))
            precondition(arrowDocument.annotations[0].arrow?.from ==
                         CGPoint(x: from.x + 2, y: from.y + 3))
            arrowDocument.undo()
            precondition(arrowDocument.annotations[0].arrow?.to == to)
        }
        var horizontal = CaptureEditorDocument(image: blank)
        precondition(horizontal.add(frame: CGRect(x: 20, y: 48, width: 56, height: 0)) != nil)
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let p3Context = CGContext(data: nil, width: 96, height: 96, bitsPerComponent: 8,
                                  bytesPerRow: 384, space: p3,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var p3Document = CaptureEditorDocument(image: p3Context.makeImage()!)
        p3Document.pick(.blur)
        p3Document.add(frame: box)
        let p3Result = try CaptureEditorRender.flatten(p3Document)
        precondition(p3Result.colorSpace?.name == CGColorSpace.displayP3)
        print("CaptureEditor eight arrow directions, endpoint movement and Display P3 PASSED")
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
