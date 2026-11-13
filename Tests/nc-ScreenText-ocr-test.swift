// notchcast-sources: Tinycast/Features/CaptureArea/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureArea/Service/*.swift
// notchcast-sources: Tinycast/Features/ScreenText/Model/*.swift
// notchcast-sources: Tinycast/Features/ScreenText/Service/*.swift
import Foundation
import CoreImage
import AppKit

@main
enum ScreenTextTest {
    @MainActor
    static func main() async throws {
        let frame = CGRect(x: -1200, y: 300, width: 1200, height: 800)
        let selection = CaptureAreaSelection.make(
            from: CGPoint(x: -100, y: 1000), to: CGPoint(x: -1000, y: 400),
            displayID: 2, displayFrame: frame, mainDisplayHeight: 900)!
        precondition(selection.rect == CGRect(x: -1000, y: -100, width: 900, height: 600))
        precondition(selection.displayFrame == CGRect(x: -1200, y: -200, width: 1200, height: 800))
        precondition(selection.sourceRect == CGRect(x: 200, y: 100, width: 900, height: 600))
        precondition(CaptureAreaSelection.make(
            from: .zero, to: .zero, displayID: 1, displayFrame: frame, mainDisplayHeight: 900) == nil)
        let clipped = CaptureAreaSelection.make(
            from: CGPoint(x: -1400, y: 200), to: CGPoint(x: -1000, y: 500),
            displayID: 2, displayFrame: frame, mainDisplayHeight: 900)!
        precondition(clipped.rect == CGRect(x: -1200, y: 400, width: 200, height: 200))
        for verticalOrigin: CGFloat in [-900, 0, 900] {
            let display = CGRect(x: 0, y: verticalOrigin, width: 1440, height: 900)
            let area = CaptureAreaSelection.make(
                from: CGPoint(x: 10, y: verticalOrigin + 20),
                to: CGPoint(x: 110, y: verticalOrigin + 220),
                displayID: 1, displayFrame: display, mainDisplayHeight: 900)!
            precondition(area.rect == CGRect(x: 10, y: 680 - verticalOrigin, width: 100, height: 200))
            precondition(area.sourceRect == CGRect(x: 10, y: 680, width: 100, height: 200))
        }
        var requestedPermission = false
        let denied = CaptureAreaService(
            hasScreenRecordingAccess: { false },
            requestScreenRecordingAccess: { requestedPermission = true; return false })
        do {
            try denied.start { _ in preconditionFailure("Denied selection must not start") }
            preconditionFailure("Permission denial must throw")
        } catch CaptureFailure.permissionDenied {
            precondition(requestedPermission)
        }
        precondition(ScreenTextResult.removingLineBreaks("  Hello\nworld \n\nNext\nparagraph ")
            == "Hello world\n\nNext paragraph")
        precondition(ScreenTextResult.removingLineBreaks("rozpozna-\nwanie\r\ntekstu") == "rozpoznawanie tekstu")
        precondition(ScreenTextResult.removingLineBreaks("one-\nTwo\n\n\nthree") == "one- Two\n\nthree")
        precondition(ScreenTextResult.removingLineBreaks(" \n\n") == "")
        precondition(ScreenTextResult.removingLineBreaks("state-\nof-the-art") == "state- of-the-art")
        precondition(ScreenTextResult.removingLineBreaks("well-known-\ncompound") == "well-known- compound")
        precondition(ScreenTextResult.removingLineBreaks("Word-\nfragment") == "Word- fragment")
        precondition(ScreenTextResult.removingLineBreaks("comput-\ning.") == "computing.")
        precondition(ScreenTextResult.removingLineBreaks("comput-\ning, then") == "computing, then")
        precondition(ScreenTextResult.removingLineBreaks("state-\nof-the-art.") == "state- of-the-art.")
        precondition(ScreenTextResult.removingLineBreaks("one-\n.") == "one- .")
        precondition(ScreenTextResult.removingLineBreaks("„so ge-\nnau“ hier") == "„so genau“ hier")
        precondition(ScreenTextResult.removingLineBreaks("«le docu-\nment»") == "«le document»")
        precondition(ScreenTextResult.removingLineBreaks("‹sehr ge-\nnau›") == "‹sehr genau›")
        precondition(ScreenTextResult.removingLineBreaks("«docu-\nment»") == "«document»")
        precondition(ScreenTextResult.removingLineBreaks("„ver-\nmutlich“ hier") == "„vermutlich“ hier")
        precondition(ScreenTextResult.removingLineBreaks("“docu-\nment”") == "“document”")
        precondition(ScreenTextResult.removingLineBreaks("state-\nof-the-art»") == "state- of-the-art»")
        precondition(ScreenTextResult.removingLineBreaks("Word-\nfragment«") == "Word- fragment«")
        precondition(ScreenTextResult.removingLineBreaks("one-\n»") == "one- »")
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data("https://example.com/ocr".utf8), forKey: "inputMessage")
        let code = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let image = CIContext().createCGImage(code, from: code.extent)!
        let result = try await ScreenTextService.recognize(image: image)
        precondition(result == ScreenTextResult(content: "https://example.com/ocr", kind: .qrCode))
        let textImage = NSImage(size: CGSize(width: 1000, height: 160))
        textImage.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 1000, height: 160).fill()
        ("Hello world" as NSString).draw(
            at: CGPoint(x: 40, y: 50),
            withAttributes: [.font: NSFont.systemFont(ofSize: 64), .foregroundColor: NSColor.black])
        textImage.unlockFocus()
        let raster = textImage.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let text = try await ScreenTextService.recognize(image: raster)
        precondition(text.kind == .text && text.content.contains("Hello world"))
        do {
            _ = try await ScreenTextService.recognize(selection: selection, content: { ([], []) })
            preconditionFailure("A removed display must fail")
        } catch ScreenTextService.Failure.displayUnavailable {}
        let blank = NSImage(size: CGSize(width: 1000, height: 500))
        blank.lockFocus()
        NSColor.white.setFill()
        CGRect(x: 0, y: 0, width: 1000, height: 500).fill()
        blank.unlockFocus()
        do {
            _ = try await ScreenTextService.recognize(
                image: blank.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            preconditionFailure("Blank selection must fail")
        } catch ScreenTextService.Failure.noContent {}
        for gap: CGFloat in [5, 90] {
            let fixture = NSImage(size: CGSize(width: 1000, height: 500))
            fixture.lockFocus()
            NSColor.white.setFill()
            CGRect(x: 0, y: 0, width: 1000, height: 500).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black]
            ("First sentence" as NSString).draw(at: CGPoint(x: 40, y: 350), withAttributes: attributes)
            ("Second sentence" as NSString).draw(at: CGPoint(x: 40, y: 290 - gap), withAttributes: attributes)
            fixture.unlockFocus()
            let raster = fixture.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let result = try await ScreenTextService.recognize(image: raster)
            precondition(result.content == "First sentence" + (gap == 5 ? "\n" : "\n\n") + "Second sentence")
        }
        for name in ["CIQRCodeGenerator", "CICode128BarcodeGenerator"] {
            let generator = CIFilter(name: name)!
            generator.setValue(Data("fixture123".utf8), forKey: "inputMessage")
            let code = generator.outputImage!
            let context = CIContext()
            let raster = context.createCGImage(code, from: code.extent)!
            let fixture = NSImage(size: CGSize(width: 1200, height: 700))
            fixture.lockFocus()
            NSColor.white.setFill()
            CGRect(x: 0, y: 0, width: 1200, height: 700).fill()
            NSGraphicsContext.current!.imageInterpolation = .none
            NSImage(cgImage: raster, size: code.extent.size).draw(
                in: CGRect(x: 100, y: 200, width: name == "CIQRCodeGenerator" ? 350 : 900, height: 350))
            ("Caption below code" as NSString).draw(at: CGPoint(x: 100, y: 50), withAttributes: [
                .font: NSFont.systemFont(ofSize: 48), .foregroundColor: NSColor.black])
            fixture.unlockFocus()
            let result = try await ScreenTextService.recognize(
                image: fixture.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
            precondition(result == ScreenTextResult(content: "fixture123",
                kind: name == "CIQRCodeGenerator" ? .qrCode : .barcode))
        }
        print("ScreenText: geometry and text processing passed")
    }
}
