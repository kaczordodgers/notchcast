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
    private var previousFrame: [UInt64]
    private var leadingRows = 0
    private var trailingRows = 0
    private(set) var limitReached: Bool

    var height: Int { log.rows.count }

    init?(first: CGImage, hashes: [UInt64], limit: Int = maximumHeight) {
        guard limit > 0, hashes.count == first.height else { return nil }
        self.limit = min(limit, Self.maximumHeight)
        width = first.width
        frameHeight = first.height
        previousFrame = hashes
        let kept = min(first.height, self.limit)
        guard let piece = Self.piece(of: first, firstRow: 0, height: kept) else { return nil }
        pieces = [piece]
        log.append(hashes.prefix(kept))
        limitReached = kept == self.limit
    }

    mutating func add(_ frame: CGImage, hashes: [UInt64]) -> Update {
        guard !limitReached else { return .limitReached }
        guard frame.width == width, frame.height == frameHeight, hashes.count == frameHeight else { return .unmatched }
        if hashes == previousFrame { return .unchanged }
        var update = Update.unmatched
        if leadingRows == 0 || trailingRows == 0, var cropped = croppingStickyBars(matching: hashes) {
            update = cropped.place(frame, hashes: hashes)
            if update != .unmatched, update != .unchanged { self = cropped }
        }
        if update == .unmatched { update = place(frame, hashes: hashes) }
        if update != .unmatched { previousFrame = hashes }
        return update
    }

    private func croppingStickyBars(matching hashes: [UInt64]) -> ScrollingStitcher? {
        let rows = log.rows
        let top = leadingRows
        let bottom = frameHeight - trailingRows
        var leading = 0
        var trailing = 0
        if leadingRows == 0 { while leading < bottom, hashes[leading] == rows[leading] { leading += 1 } }
        if trailingRows == 0 {
            while trailing < bottom - top - leading, hashes[bottom - trailing - 1] == rows[rows.count - trailing - 1] {
                trailing += 1
            }
        }
        let minimumStickyRows = max(1, frameHeight / 10)
        if leading < minimumStickyRows { leading = 0 }
        if trailing < minimumStickyRows { trailing = 0 }
        guard leading + trailing > 0, leading + trailing < bottom - top else { return nil }
        var middle = ScrollingRowLog()
        middle.append(rows[leading..<rows.count - trailing])
        let content = Array(hashes[top + leading..<bottom - trailing])
        guard let start = middle.placement(of: content, minimumOverlap: Self.minimumOverlap(content.count)) else {
            return nil
        }
        // A band is only chrome if the scroll that moved the middle did not move it with it.
        if start >= 0, hashes[..<leading] == rows[start..<start + leading] { leading = 0 }
        let shift = start - top
        if rows.count - shift <= frameHeight,
           rows[(rows.count - trailing)...] == hashes[(rows.count - trailing - shift)..<(rows.count - shift)] {
            trailing = 0
        }
        guard leading + trailing > 0 else { return nil }
        var next = self
        var dropped = 0
        while dropped < trailing, let last = next.pieces.popLast() {
            dropped += last.height
            if dropped > trailing {
                guard let kept = Self.piece(of: last, firstRow: 0, height: dropped - trailing) else { return nil }
                next.pieces.append(kept)
            }
        }
        guard let top = next.pieces.first,
              let cropped = Self.piece(of: top, firstRow: leading, height: top.height - leading) else { return nil }
        next.pieces[0] = cropped
        next.log = ScrollingRowLog()
        next.log.append(rows[leading..<rows.count - trailing])
        next.leadingRows += leading
        next.trailingRows += trailing
        return next
    }

    private static func minimumOverlap(_ count: Int) -> Int { min(count, max(16, count / 8)) }

    private mutating func place(_ frame: CGImage, hashes: [UInt64]) -> Update {
        var leading = leadingRows
        var trailing = trailingRows
        // A bar's flat edge may be chance-matched page rows; only varied rows replacing it prove a scroll.
        if leading > 1, case let edge = previousFrame[leading - 1], previousFrame[leading - 2] == edge {
            while leading > 0, previousFrame[leading - 1] == edge, hashes[leading - 1] != edge { leading -= 1 }
            if Set(hashes[leading..<leadingRows]).count < 2 { leading = leadingRows }
        }
        if trailing > 1, case let edge = previousFrame[frameHeight - trailing],
           previousFrame[frameHeight - trailing + 1] == edge {
            while trailing > 0, previousFrame[frameHeight - trailing] == edge, hashes[frameHeight - trailing] != edge {
                trailing -= 1
            }
            if Set(hashes[frameHeight - trailingRows..<frameHeight - trailing]).count < 2 { trailing = trailingRows }
        }
        let minimumOverlap = Self.minimumOverlap(frameHeight - leadingRows - trailingRows)
        var content = Array(hashes[leading..<frameHeight - trailing])
        var placed = log.placement(of: content, minimumOverlap: minimumOverlap)
        // A bar that only changed shade is still a bar.
        if placed == nil, leading != leadingRows || trailing != trailingRows {
            (leading, trailing) = (leadingRows, trailingRows)
            content = Array(hashes[leading..<frameHeight - trailing])
            placed = log.placement(of: content, minimumOverlap: minimumOverlap)
        }
        guard let start = placed else { return .unmatched }
        leadingRows = leading
        trailingRows = trailing
        let added = start + content.count - height
        guard start >= 0, added > 0 else { return .unchanged }
        let take = min(added, limit - height)
        let first = content.count - added
        guard let piece = Self.piece(of: frame, firstRow: leadingRows + first, height: take) else { return .unmatched }
        log.append(content[first..<first + take])
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
