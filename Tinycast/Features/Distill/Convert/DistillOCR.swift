import CoreGraphics
import Foundation
import ImageIO
import Vision

nonisolated enum DistillOCR {
    static func image(at source: URL) throws -> CGImage {
        guard let container = CGImageSourceCreateWithURL(source as CFURL, nil),
            CGImageSourceGetCount(container) > 0,
            let image = CGImageSourceCreateThumbnailAtIndex(container, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
            ] as CFDictionary)
        else { throw DistillConversion.Failure.unreadable }
        return image
    }

    static func recognize(_ image: CGImage) async throws -> String {
        try Task.checkCancellation()
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.minimumTextHeightFraction = 0
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: image)
        try Task.checkCancellation()
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
