import CoreGraphics

struct ScrollingStitcher: Sendable {
    static let maximumHeight = 20_000

    enum Update: Equatable, Sendable {
        case added(Int)
        case unchanged
        case unmatched
        case limitReached
    }

    private var log = ScrollingRowLog()
    private var pieces: [CGImage]
    private let width: Int
    private let frameHeight: Int
    private let limit: Int
    private(set) var limitReached: Bool

    var height: Int { log.rows.count }

    init?(first: CGImage, hashes: [UInt64], limit: Int = maximumHeight) {
        guard limit > 0, hashes.count == first.height else { return nil }
        self.limit = min(limit, Self.maximumHeight)
        width = first.width
        frameHeight = first.height
        let kept = min(first.height, self.limit)
        guard let piece = Self.piece(of: first, firstRow: 0, height: kept) else { return nil }
        pieces = [piece]
        log.append(hashes.prefix(kept))
        limitReached = kept == self.limit
    }

    mutating func add(_ frame: CGImage, hashes: [UInt64]) -> Update {
        guard !limitReached else { return .limitReached }
        guard frame.width == width, frame.height == frameHeight, hashes.count == frameHeight else { return .unmatched }
        if hashes == log.rows.suffix(frameHeight) { return .unchanged }
        let minimumOverlap = min(frameHeight, max(16, frameHeight / 8))
        guard let start = log.placement(of: hashes, minimumOverlap: minimumOverlap) else { return .unmatched }
        let added = start + frameHeight - height
        guard start >= 0, added > 0 else { return .unchanged }
        let take = min(added, limit - height)
        let first = frameHeight - added
        guard let piece = Self.piece(of: frame, firstRow: first, height: take) else { return .unmatched }
        log.append(hashes[first..<first + take])
        pieces.append(piece)
        limitReached = height == limit
        return limitReached ? .limitReached : .added(take)
    }

    func image() -> CGImage? {
        guard pieces.count > 1 else { return pieces.first }
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        var top = height
        for piece in pieces {
            top -= piece.height
            context.draw(piece, in: CGRect(x: 0, y: top, width: width, height: piece.height))
        }
        return context.makeImage()
    }

    private static func piece(of image: CGImage, firstRow: Int, height: Int) -> CGImage? {
        if firstRow == 0, height == image.height { return image }
        guard let crop = image.cropping(to: CGRect(x: 0, y: firstRow, width: image.width, height: height)),
              let context = CGContext(
                  data: nil, width: image.width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        // A retained crop can otherwise keep the entire source frame's pixel storage alive.
        context.interpolationQuality = .none
        context.draw(crop, in: CGRect(x: 0, y: 0, width: image.width, height: height))
        return context.makeImage()
    }
}
