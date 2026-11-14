// notchcast-sources: Tinycast/Features/MediaTools/Service/*.swift Tinycast/Features/Notchcast/Jobs/JobOutput.swift
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

        let scanned = root.appendingPathComponent("scanned.pdf")
        var page = CGRect(x: 0, y: 0, width: 600, height: 300)
        let scan = CGContext(data: nil, width: 1200, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        scan.setFillColor(CGColor(gray: 1, alpha: 1))
        scan.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
        let body = CTLineCreateWithAttributedString(NSAttributedString(string: "Scanned invoice body",
            attributes: [.font: NSFont.systemFont(ofSize: 72)]) as CFAttributedString)
        scan.textPosition = CGPoint(x: 60, y: 260)
        CTLineDraw(body, scan)
        let stamped = CGContext(scanned as CFURL, mediaBox: &page, nil)!
        stamped.beginPDFPage(nil)
        stamped.draw(scan.makeImage()!, in: page)
        let stamp = CTLineCreateWithAttributedString(NSAttributedString(string: "p1",
            attributes: [.font: NSFont.systemFont(ofSize: 10)]) as CFAttributedString)
        stamped.textPosition = CGPoint(x: 570, y: 10)
        CTLineDraw(stamp, stamped)
        stamped.endPDFPage()
        stamped.closePDF()
        let scannedText = try String(contentsOf: try await runner.run(scanned, tool: .text), encoding: .utf8)
        precondition(scannedText.contains("Scanned invoice body"), "A stamped scan still gets OCR: \(scannedText)")
        let bad = root.appendingPathComponent("bad.bin")
        try Data([1, 2, 3]).write(to: bad)
        do { _ = try await runner.run(bad, tool: .image()); fatalError("Unsupported input accepted")
        } catch MediaToolsRunner.Failure.unsupported {}

        let video = root.appendingPathComponent("video.mov")
        try await fixture(video)
        let output = try await runner.run(video, tool: .video())
        let asset = AVURLAsset(url: output)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        precondition(audioTracks.count == 1, "Video encoding must preserve audio")
        let audioDuration = try await audioTracks[0].load(.timeRange).duration.seconds
        precondition(audioDuration >= 0.9, "Encoded audio must cover the fixture")
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
        let silent = url.deletingPathExtension().appendingPathExtension("silent.mov")
        let audio = url.deletingPathExtension().appendingPathExtension("caf")
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mov)
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
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100)!
        buffer.frameLength = 44100
        for channel in 0..<2 {
            for frame in 0..<44100 {
                buffer.floatChannelData![channel][frame] = Float(sin(Double(frame) * 2 * .pi * 440 / 44100)) * 0.1
            }
        }
        do {
            let file = try AVAudioFile(forWriting: audio, settings: format.settings)
            try file.write(from: buffer)
        }
        let composition = AVMutableComposition()
        for (source, type) in [(silent, AVMediaType.video), (audio, AVMediaType.audio)] {
            let asset = AVURLAsset(url: source)
            let track = try await asset.loadTracks(withMediaType: type).first!
            let destination = composition.addMutableTrack(withMediaType: type,
                preferredTrackID: kCMPersistentTrackID_Invalid)!
            try destination.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 44100)),
                of: track, at: .zero)
        }
        let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        try await export.export(to: url, as: .mov)
        let fixtureAudio = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        precondition(fixtureAudio.count == 1)
    }
}
