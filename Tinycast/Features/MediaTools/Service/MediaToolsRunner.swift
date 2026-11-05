import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

struct MediaToolsRunner: Sendable {
    enum Tool: Sendable {
        case video(targetBytes: Int? = nil)
        case gif
        case image(maxDimension: Int = 1600)
        case text
    }

    enum Failure: LocalizedError {
        case unsupported, invalidOptions, encoding, targetTooSmall, gifLimit

        var errorDescription: String? {
            switch self {
            case .unsupported: String(localized: "This media format is not supported.", table: "Notchcast")
            case .invalidOptions: String(localized: "The media options are invalid.", table: "Notchcast")
            case .encoding: String(localized: "Media encoding failed.", table: "Notchcast")
            case .targetTooSmall: String(localized: "The requested media size is too small.", table: "Notchcast")
            case .gifLimit: String(localized: "GIFs support videos up to 30 seconds at 12 fps and 480 pixels.", table: "Notchcast")
            }
        }
    }

    @concurrent
    func run(_ input: URL, tool: Tool) async throws -> URL {
        try Task.checkCancellation()
        guard input.isFileURL,
              try input.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        else { throw Failure.unsupported }
        let directory = input.deletingLastPathComponent()
            .appendingPathComponent(".media-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suffix: String
        switch tool {
        case .video: suffix = "mp4"
        case .gif: suffix = "gif"
        case .image: suffix = "jpg"
        case .text: suffix = "txt"
        }
        let staged = directory.appendingPathComponent("output." + suffix)
        switch tool {
        case let .video(target): try await video(input, output: staged, target: target)
        case .gif: try await gif(input, output: staged)
        case let .image(dimension): try image(input, output: staged, dimension: dimension)
        case .text:
            let text = try extract(input)
            try text.write(to: staged, atomically: false, encoding: .utf8)
        }
        try Task.checkCancellation()
        for index in 1...10000 {
            let name = input.deletingPathExtension().lastPathComponent + " processed (\(index))." + suffix
            let destination = input.deletingLastPathComponent().appendingPathComponent(name)
            do {
                try FileManager.default.linkItem(at: staged, to: destination)
                return destination
            } catch CocoaError.fileWriteFileExists { continue }
        }
        throw Failure.encoding
    }

    private func image(_ input: URL, output: URL, dimension: Int) throws {
        guard (1...1600).contains(dimension) else { throw Failure.invalidOptions }
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: dimension,
              ] as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(
                output as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Failure.unsupported }
        try Task.checkCancellation()
        CGImageDestinationAddImage(destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.encoding }
    }

    private func extract(_ input: URL) throws -> String {
        if input.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: input), !document.isLocked else { throw Failure.unsupported }
            return try (0..<document.pageCount).map { index in
                try Task.checkCancellation()
                guard let page = document.page(at: index) else { throw Failure.unsupported }
                if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return text
                }
                let thumbnail = page.thumbnail(of: CGSize(width: 1600, height: 1600), for: .mediaBox)
                guard let data = thumbnail.tiffRepresentation,
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
                else { throw Failure.unsupported }
                return try recognize(image)
            }.joined(separator: "\n")
        }
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 3200,
              ] as CFDictionary)
        else { throw Failure.unsupported }
        return try recognize(image)
    }

    private func recognize(_ image: CGImage) throws -> String {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: image).perform([request])
        try Task.checkCancellation()
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private func gif(_ input: URL, output: URL) async throws {
        let asset = AVURLAsset(url: input)
        guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw Failure.unsupported }
        let seconds = try await asset.load(.duration).seconds
        guard seconds.isFinite, seconds > 0, seconds <= 30 else { throw Failure.gifLimit }
        let count = Int(ceil(seconds * 12))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        defer { generator.cancelAllCGImageGeneration() }
        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.gif.identifier as CFString, count, nil)
        else { throw Failure.encoding }
        CGImageDestinationSetProperties(destination,
            [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<count {
            try Task.checkCancellation()
            let frame = try await generator.image(at: CMTime(value: Int64(index), timescale: 12)).image
            CGImageDestinationAddImage(destination, frame,
                [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 12]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw Failure.encoding }
    }

    private func video(_ input: URL, output: URL, target: Int?) async throws {
        if let target, target < 4096 { throw Failure.targetTooSmall }
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw Failure.unsupported }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw Failure.unsupported }
        let size = try await track.load(.naturalSize)
        let scale = min(1, 1280 / max(size.width, size.height))
        let width = max(2, Int(size.width * scale) / 2 * 2)
        let height = max(2, Int(size.height * scale) / 2 * 2)
        let transform = try await track.load(.preferredTransform)
        var bitrate = target.map { Double($0) * 8 / duration * 0.8 }
        for _ in 0..<4 {
            try Task.checkCancellation()
            if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
            let reader = try AVAssetReader(asset: asset)
            let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
            var compression: [String: Any] = [AVVideoQualityKey: 0.68,
                AVVideoExpectedSourceFrameRateKey: 30]
            if let bitrate { compression = [AVVideoAverageBitRateKey: max(1000, Int(bitrate))] }
            let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width,
                AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: compression,
            ])
            videoInput.transform = transform
            let videoOutput = AVAssetReaderTrackOutput(track: track,
                outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            typealias Sample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>
            typealias Provider = AVAssetReaderOutput.Provider<Sample>
            var pairs: [(Provider, AVAssetWriterInput.SampleBufferReceiver)] = [
                (reader.outputProvider(for: videoOutput), writer.inputReceiver(for: videoInput)),
            ]
            if let audio = try await asset.loadTracks(withMediaType: .audio).first {
                let audioOutput = AVAssetReaderTrackOutput(track: audio,
                    outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 64000,
                ])
                pairs.append((reader.outputProvider(for: audioOutput), writer.inputReceiver(for: audioInput)))
            }
            try writer.start()
            try reader.start()
            writer.startSession(atSourceTime: .zero)
            var completed = Set<Int>()
            var lastFrame = -Double.infinity
            var pending: [Int: Sample] = [:]
            do {
                while completed.count < pairs.count {
                    try Task.checkCancellation()
                    guard writer.status == .writing else { throw writer.error ?? Failure.encoding }
                    for (index, pair) in pairs.enumerated() where !completed.contains(index) {
                        let next: Sample?
                        if let sample = pending[index] {
                            next = sample
                        } else {
                            next = try await pair.0.next()
                        }
                        guard let sample = next else {
                            pair.1.finish()
                            completed.insert(index)
                            continue
                        }
                        if index == 0 && pending[index] == nil {
                            let time = sample.presentationTimeStamp.seconds
                            if time - lastFrame < 1.0 / 30 - 0.00001 { continue }
                            lastFrame = time
                        }
                        if try pair.1.appendImmediately(sample) {
                            pending[index] = nil
                        } else {
                            pending[index] = sample
                        }
                    }
                    try await Task.sleep(for: .milliseconds(1))
                }
                guard reader.status == .completed else { throw reader.error ?? Failure.encoding }
                await writer.finishWriting()
                try Task.checkCancellation()
                guard writer.status == .completed else { throw writer.error ?? Failure.encoding }
            } catch {
                reader.cancelReading()
                writer.cancelWriting()
                throw error
            }
            let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if let target, bytes > target {
                bitrate = (bitrate ?? 1000) * min(0.7, Double(target) / Double(bytes) * 0.8)
            } else { return }
        }
        throw Failure.targetTooSmall
    }
}
