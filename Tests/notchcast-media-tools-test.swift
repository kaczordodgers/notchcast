// notchcast-sources: Tinycast/Features/MediaTools/Service/*.swift
import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

@main
struct MediaToolsTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = MediaToolsRunner()
        let image = root.appendingPathComponent("fixture.png")
        let context = CGContext(data: nil, width: 2000, height: 1000, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        let destination = CGImageDestinationCreateWithURL(image as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private fixture"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 45.0],
        ] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        let compressed = try await runner.run(image, tool: .image())
        let second = try await runner.run(image, tool: .image(maxDimension: 800))
        precondition(compressed != second && compressed != image)
        let source = CGImageSourceCreateWithURL(compressed as CFURL, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        precondition(properties[kCGImagePropertyPixelWidth] as? Int == 1600)
        let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary
        precondition(exif?[kCGImagePropertyExifUserComment] == nil)
        precondition(properties[kCGImagePropertyGPSDictionary] == nil)

        let pdf = root.appendingPathComponent("text.pdf")
        var box = CGRect(x: 0, y: 0, width: 400, height: 200)
        let pdfContext = CGContext(pdf as CFURL, mediaBox: &box, nil)!
        pdfContext.beginPDFPage(nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Synthetic media text",
            attributes: [.font: NSFont.systemFont(ofSize: 24)]) as CFAttributedString)
        pdfContext.textPosition = CGPoint(x: 20, y: 100)
        CTLineDraw(line, pdfContext)
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        let text = try await runner.run(pdf, tool: .text)
        let extracted = try String(contentsOf: text, encoding: .utf8)
        precondition(extracted.contains("Synthetic media text"))
        let bad = root.appendingPathComponent("bad.bin")
        try Data([1, 2, 3]).write(to: bad)
        do { _ = try await runner.run(bad, tool: .image()); fatalError("Unsupported input accepted")
        } catch MediaToolsRunner.Failure.unsupported {}

        let video = root.appendingPathComponent("video.mov")
        try await fixture(video)
        let output = try await runner.run(video, tool: .video())
        let asset = AVURLAsset(url: output)
        let track = try await asset.loadTracks(withMediaType: .video).first!
        let size = try await track.load(.naturalSize)
        let fps = try await track.load(.nominalFrameRate)
        precondition(max(size.width, size.height) <= 1280 && fps <= 30.01)
        let target = try await runner.run(video, tool: .video(targetBytes: 100000))
        let targetSize = try target.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        precondition(targetSize <= 100000)
        let gif = try await runner.run(video, tool: .gif)
        let gifSource = CGImageSourceCreateWithURL(gif as CFURL, nil)!
        let gifProperties = CGImageSourceCopyPropertiesAtIndex(gifSource, 0, nil)! as NSDictionary
        precondition((gifProperties[kCGImagePropertyPixelWidth] as? Int ?? 1000) <= 720)
        precondition(CGImageSourceGetCount(gifSource) <= 13)
        let timing = gifProperties[kCGImagePropertyGIFDictionary] as? NSDictionary
        precondition(abs((timing?[kCGImagePropertyGIFDelayTime] as? Double ?? 0) - 1.0 / 12) < 0.02)
        let before = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        let task = Task { try await runner.run(video, tool: .gif) }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()
        do { _ = try await task.value; fatalError("Cancellation ignored") } catch is CancellationError {}
        let after = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        precondition(after == before)
        print("Media limits, target size, metadata, publication, text, unsupported input and cancellation passed")
    }

    static func fixture(_ url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1440, AVVideoHeightKey: 800,
        ])
        let receiver = writer.inputPixelBufferReceiver(for: input, pixelBufferAttributes: nil)
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        for index in 0..<60 {
            var buffer: CVPixelBuffer?
            precondition(CVPixelBufferCreate(nil, 1440, 800, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(index * 3), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            let frame = CVReadOnlyPixelBuffer(unsafeBuffer: buffer!)
            try await receiver.append(frame, with: CMTime(value: Int64(index), timescale: 60))
        }
        receiver.finish()
        await writer.finishWriting()
        precondition(writer.status == .completed)
    }
}
