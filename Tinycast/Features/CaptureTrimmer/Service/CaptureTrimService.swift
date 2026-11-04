import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum CaptureTrimService {
    enum Failure: Error { case invalidRange, unavailable, cannotWrite }

    @concurrent static func save(
        source: URL, trim: CaptureTrim, destination: URL, files: FileManager = .default
    ) async throws -> URL {
        guard source != destination, trim.end > trim.start else { throw Failure.invalidRange }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, trim.end <= duration + 0.001 else { throw Failure.invalidRange }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString + (trim.format == .mp4 ? ".mp4" : ".gif"))
        defer { try? files.removeItem(at: temporary) }
        switch trim.format {
        case .mp4:
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
            else { throw Failure.unavailable }
            exporter.timeRange = CMTimeRange(
                start: CMTime(seconds: trim.start, preferredTimescale: 600),
                end: CMTime(seconds: trim.end, preferredTimescale: 600))
            try await exporter.export(to: temporary, as: .mp4)
        case .gif:
            try await gif(asset: asset, trim: trim, destination: temporary)
        }
        try Task.checkCancellation()
        try files.moveItem(at: temporary, to: destination)
        return destination
    }

    private static func gif(asset: AVURLAsset, trim: CaptureTrim, destination: URL) async throws {
        let count = Int(ceil((trim.end - trim.start) * 15))
        let writer = try CaptureGIFWriter(url: destination)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 800, height: 800)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        for index in 0..<count {
            try Task.checkCancellation()
            let time = trim.start + Double(index) / 15
            let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
            let delay = min(1 / 15.0, trim.end - time)
            try writer.append(image, delay: delay)
        }
        try writer.finish()
    }

    @concurrent static func recoverable(in folder: URL, files: FileManager = .default) async throws -> [URL] {
        guard files.fileExists(atPath: folder.path) else { return [] }
        return try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]).filter {
                guard ["mov", "mp4"].contains($0.pathExtension.lowercased()) else { return false }
                return try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
