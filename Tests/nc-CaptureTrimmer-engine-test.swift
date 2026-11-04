// notchcast-sources: Tinycast/Features/CaptureTrimmer/Model/*.swift
// notchcast-sources: Tinycast/Features/CaptureTrimmer/Service/CaptureTrimService.swift
// notchcast-sources: Tinycast/Features/CaptureTrimmer/Service/CaptureGIFWriter.swift
// notchcast-sources: Tinycast/Features/CaptureTrimmer/Service/CaptureTrimmerModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
import AVFoundation
import ImageIO

@main
struct CaptureTrimmerTest {
    @MainActor static func main() async throws {
        var trim = CaptureTrim(duration: 2, framesPerSecond: 30)
        trim.set(.start, to: 9)
        precondition(abs(trim.start - (2 - 1 / 30.0)) < 0.0001)
        trim.set(.start, to: -2)
        trim.seek(to: 1)
        trim.markStart()
        precondition(trim.start == 1)
        trim.selected = .end
        trim.step(direction: -1, bySecond: true)
        precondition(trim.end > trim.start)
        trim.set(.end, to: .nan)
        trim.togglePlayback()
        precondition(trim.isPlaying)
        precondition(CaptureTrim(duration: .nan, framesPerSecond: 0).duration == 0)

        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mov")
        try await video(at: source)
        let found = try await CaptureTrimService.recoverable(in: folder)
        precondition(found.map(\.standardizedFileURL) == [source.standardizedFileURL])
        var cut = CaptureTrim(duration: 1, framesPerSecond: 15)
        cut.set(.start, to: 0.2)
        cut.set(.end, to: 0.8)
        let mp4 = folder.appendingPathComponent("result.mp4")
        _ = try await CaptureTrimService.save(source: source, trim: cut, destination: mp4)
        let length = try await AVURLAsset(url: mp4).load(.duration).seconds
        precondition(abs(length - 0.6) < 0.1)
        cut.format = .gif
        let gif = folder.appendingPathComponent("result.gif")
        _ = try await CaptureTrimService.save(source: source, trim: cut, destination: gif)
        let images = CGImageSourceCreateWithURL(gif as CFURL, nil)!
        precondition(CGImageSourceGetCount(images) == 10 || CGImageSourceGetCount(images) == 9)
        for index in 0..<CGImageSourceGetCount(images) {
            precondition(CGImageSourceCreateImageAtIndex(images, index, nil) != nil)
        }
        do {
            _ = try await CaptureTrimService.save(source: source, trim: cut, destination: gif)
            preconditionFailure("must not overwrite")
        } catch {}
        let suite = "trimmer-test-" + UUID().uuidString
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        var copied: URL?
        let module = CaptureTrimmerModule(workFolder: folder) { copied = $0 }
        preferences.set(.captureTrimmer, true)
        let controller = NotchcastModuleController([
            .init(requires: [.captureTrimmer], module: module)], preferences: preferences)
        controller.run()
        precondition(module.enabled)
        _ = try await module.save(source: source, trim: cut,
            destination: folder.appendingPathComponent("copy.gif"), copy: true)
        precondition(copied != nil)
        preferences.set(.captureTrimmer, false)
        for _ in 0..<100 where module.enabled { await Task.yield() }
        precondition(!module.enabled)
        do {
            _ = try await module.save(source: source, trim: cut, destination: gif)
            preconditionFailure("disabled")
        } catch is CancellationError {}
        print("PASS: range, MP4, GIF, recovery, clipboard, switch lifecycle")
    }

    static func video(at url: URL) async throws {
        let writer = try AVAssetWriter(url: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<15 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var pixel: CVPixelBuffer?
            precondition(CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixel) == kCVReturnSuccess)
            precondition(adaptor.append(pixel!, withPresentationTime: CMTime(value: Int64(frame), timescale: 15)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        precondition(writer.status == .completed)
    }
}
