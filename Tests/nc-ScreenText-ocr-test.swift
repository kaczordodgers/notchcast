// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/*.swift
// notchcast-sources: Tinycast/Features/ScreenText/Model/*.swift
// notchcast-sources: Tinycast/Features/ScreenText/Service/*.swift
import Foundation
import CoreImage

@main
enum ScreenTextTest {
    static func main() async throws {
        let frame = CGRect(x: -1200, y: 300, width: 1200, height: 800)
        let selection = CaptureAreaSelection.make(
            from: CGPoint(x: -100, y: 1000), to: CGPoint(x: -1000, y: 400),
            displayID: 2, displayFrame: frame)!
        precondition(selection.rect == CGRect(x: -1000, y: 400, width: 900, height: 600))
        precondition(selection.sourceRect == CGRect(x: 200, y: 100, width: 900, height: 600))
        precondition(CaptureAreaSelection.make(
            from: .zero, to: .zero, displayID: 1, displayFrame: frame) == nil)
        let clipped = CaptureAreaSelection.make(
            from: CGPoint(x: -1400, y: 200), to: CGPoint(x: -1000, y: 500),
            displayID: 2, displayFrame: frame)!
        precondition(clipped.rect == CGRect(x: -1200, y: 300, width: 200, height: 200))
        precondition(ScreenTextResult.removingLineBreaks("  Hello\nworld \n\nNext\nparagraph ")
            == "Hello world\n\nNext paragraph")
        precondition(ScreenTextResult.removingLineBreaks("rozpozna-\nwanie\r\ntekstu") == "rozpoznawanie tekstu")
        precondition(ScreenTextResult.removingLineBreaks("one-\nTwo\n\n\nthree") == "one- Two\n\nthree")
        precondition(ScreenTextResult.removingLineBreaks(" \n\n") == "")
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data("https://example.com/ocr".utf8), forKey: "inputMessage")
        let code = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let image = CIContext().createCGImage(code, from: code.extent)!
        let result = try await ScreenTextService.recognize(image: image)
        precondition(result == ScreenTextResult(content: "https://example.com/ocr", kind: .qrCode))
        print("ScreenText: geometry and text processing passed")
    }
}
