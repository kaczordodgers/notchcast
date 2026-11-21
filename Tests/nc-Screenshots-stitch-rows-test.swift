// notchcast-sources: -O Tinycast/Features/Notchcast/Screenshots/Model/*.swift

import CoreGraphics
import Foundation

// #938 guest try 1: a page of 20 px rows whose colour encodes their position, read back row by row.

typealias Session = ScrollStitchSession

let header: (UInt8, UInt8, UInt8) = (255, 0, 128)
let footer: (UInt8, UInt8, UInt8) = (0, 128, 255)

/// Row `index`'s colour: every channel a multiple of 17, so each of 4,096 rows reads back as itself.
func colour(_ index: Int) -> (UInt8, UInt8, UInt8) {
    (UInt8((index / 256 % 16) * 17), UInt8((index / 16 % 16) * 17), UInt8((index % 16) * 17))
}

func band(_ row: Int) -> (UInt8, UInt8, UInt8) {
    let index = row / 10
    return (UInt8((index * 37) % 200 + 20), UInt8((index * 17) % 180 + 30), UInt8((index * 53) % 160 + 40))
}

func rgbImage(width: Int, height: Int, pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let (red, green, blue) = pixel(x, y)
            let offset = (y * width + x) * 4
            bytes[offset] = red
            bytes[offset + 1] = green
            bytes[offset + 2] = blue
        }
    }
    let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    return context.makeImage()!
}

struct Page {
    let width: Int
    let viewport: Int
    var stickyRows = 0
    var sidebarColumns = 0..<0
    var flatRows = 0..<0
    let rowHeight = 20

    /// The viewport scrolled to `position` px, with a sticky header and footer `stickyRows` px tall.
    func frame(at position: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * viewport * 4)
        bytes.withUnsafeMutableBufferPointer { buffer in
            for y in 0..<viewport {
                let band = y < stickyRows ? header : y >= viewport - stickyRows ? footer
                    : flatRows.contains(position + y) ? colour(flatRows.lowerBound / rowHeight)
                    : colour((position + y) / rowHeight)
                var pixel = UInt32(band.0) | UInt32(band.1) << 8 | UInt32(band.2) << 16 | 0xFF00_0000
                withUnsafeBytes(of: &pixel) {
                    memset_pattern4(buffer.baseAddress! + y * width * 4, $0.baseAddress!, width * 4)
                }
                if !sidebarColumns.isEmpty {
                    let value: UInt8 = y < viewport - 100 ? 0 : 255
                    let start = (y * width + sidebarColumns.lowerBound) * 4
                    for byte in start..<(start + sidebarColumns.count * 4) where byte & 3 != 3 {
                        buffer[byte] = value
                    }
                }
                // Text-like specks, so the bands are not flat like the rows.
                guard band == header || band == footer else { continue }
                for x in stride(from: 10 + y % 7, to: min(width, 120), by: 7) {
                    buffer[(y * width + x) * 4] = 255
                    buffer[(y * width + x) * 4 + 1] = 255
                    buffer[(y * width + x) * 4 + 2] = 255
                }
            }
        }
        let context = CGContext(data: &bytes, width: width, height: viewport, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return context.makeImage()!
    }
}

/// What each pixel row of a result shows, one column in from the left: a page row, a band, or neither.
enum Row: Equatable { case page(Int), header, footer, unknown }

/// Runs of equal rows, top to bottom, as the guest's checker reads the clipboard PNG.
func rgba(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return bytes
}

func rows(_ image: CGImage) -> [(row: Row, height: Int)] {
    let bytes = rgba(image)
    var runs: [(row: Row, height: Int)] = []
    for y in 0..<image.height {
        let offset = (y * image.width + image.width - 1) * 4
        let pixel = (bytes[offset], bytes[offset + 1], bytes[offset + 2])
        let row: Row = pixel == header ? .header : pixel == footer ? .footer
            : [pixel.0, pixel.1, pixel.2].allSatisfy({ $0 % 17 == 0 })
                ? .page(Int(pixel.0 / 17) * 256 + Int(pixel.1 / 17) * 16 + Int(pixel.2 / 17)) : .unknown
        if runs.last?.row == row { runs[runs.count - 1].height += 1 } else { runs.append((row, 1)) }
    }
    return runs
}

/// Every page row in order, none missing or doubled, each whole but the first and last.
func seamless(_ image: CGImage?, _ what: String, firstRow: Int = 0) -> [Int] {
    guard let image else { preconditionFailure("\(what): no image") }
    let pages = rows(image).compactMap { run -> (Int, Int)? in
        if case .page(let index) = run.row { return (index, run.height) }
        precondition(run.row != .unknown, "\(what): a row of no page colour")
        return nil
    }
    for (offset, page) in pages.enumerated() {
        precondition(page.0 == firstRow + offset,
                     "\(what): row \(firstRow + offset) expected, found row \(page.0)")
        precondition(offset == 0 || offset == pages.count - 1 || page.1 == 20,
                     "\(what): row \(page.0) is \(page.1) px, not 20")
    }
    return pages.map(\.0)
}

/// The run's loop on a microsecond clock; frames are made as they are asked for, so few are alive at once.
func capture(positions: [Int], frame: (Int) -> CGImage) -> (ending: Session.Ending, image: CGImage?) {
    var micros = 0
    var now: TimeInterval { Double(micros) / 1_000_000 }
    var session = Session(first: frame(positions[0]), at: now)!
    var served = 1
    while true {
        switch session.next(at: now, finishRequested: served >= positions.count) {
        case .wait(let seconds):
            micros += max(1, Int((seconds * 1_000_000).rounded(.up)))
        case .capture:
            let current = frame(positions[min(served, positions.count - 1)])
            served += 1
            micros += 10_000
            if let ending = session.take(current, at: now) { return (ending, session.stitched()) }
        case .end(let ending):
            return (ending, session.stitched())
        }
    }
}

@main
enum ScrollStitchRowsTests {
    static func main() {
        wideJump()
        heightCap()
        stickyBands()
        shortFinalScroll()
        staticSidebar(columns: 0..<224)
        staticSidebar(columns: 1_568..<1_792)
        flatSeam()
        nonzeroSeamTie()
        repeatingPastGap()
        scrollingStrip(430..<470)
        scrollingStrip(180..<720)
        mismatchRecovery()
        print("nc-Screenshots-stitch-rows-test: ok")
    }

    static func shortFinalScroll() {
        let page = Page(width: 256, viewport: 1_400)
        let run = capture(positions: [0, 160, 170], frame: page.frame)
        precondition(run.ending == .success && run.image?.height == 1_570,
                     "the final 10 px are kept: \(run.ending), \(run.image?.height ?? -1) px")
        precondition(seamless(run.image, "short final scroll").last == 78, "the last page row shows")
    }

    static func staticSidebar(columns: Range<Int>) {
        let page = Page(width: 1_792, viewport: 1_400, sidebarColumns: columns)
        let run = capture(positions: [0, 161, 322], frame: page.frame)
        precondition(run.ending == .success && run.image?.height == 1_722 && run.image?.width == page.width,
                     "a static sidebar at \(columns) keeps the full capture: \(run.ending)")
        let content = run.image?.cropping(to: CGRect(x: page.width / 2, y: 0, width: 1, height: 1_722))
        precondition(seamless(content, "scroll beside a static sidebar").last == 86, "the last page row shows")
    }

    static func flatSeam() {
        let page = Page(width: 256, viewport: 1_400, flatRows: 1_140..<1_480)
        let run = capture(positions: [0, 80, 160, 240], frame: page.frame)
        let expected = Page(width: page.width, viewport: 1_640, flatRows: page.flatRows).frame(at: 0)
        precondition(run.ending == .success && run.image?.height == expected.height,
                     "detail after a flat seam joins: \(run.ending), \(run.image?.height ?? -1) px")
        precondition(rgba(run.image!) == rgba(expected), "every row after the flat seam shows")
    }

    static func nonzeroSeamTie() {
        let previous = rgbImage(width: 16, height: 360) { _, y in y == 260 ? (0, 0, 0) : (255, 255, 255) }
        let current = rgbImage(width: 16, height: 360) { _, _ in (255, 255, 255) }
        let overlap = ScrollStitchMatcher.verifiedOverlap(
            previous: ScrollStitchImage.colourSample(previous)!, current: ScrollStitchImage.colourSample(current)!,
            overlap: 340, fixedBottomRows: 0, contentColumns: Array(0..<16))
        precondition(overlap == nil, "a tie with mismatching rows does not verify a seam")
    }

    static func repeatingPastGap() {
        let run = capture(positions: [120, 240, 680]) { position in
            rgbImage(width: 48, height: 360) { _, y in
                let row = position + y
                return (200..<620).contains(row) ? (255, 255, 255) : band(row)
            }
        }
        precondition(run.ending == .partial && run.image?.height == 360,
                     "a backward alias after a gap preserves the partial result: \(run.ending)")
    }

    static func mismatchRecovery() {
        let page = Page(width: 256, viewport: 1_400)
        let run = capture(positions: [0, 10_880, 0], frame: page.frame)
        precondition(run.ending == .success && run.image?.height == page.viewport,
                     "returning to the last kept frame clears the partial state: \(run.ending)")
    }

    static func scrollingStrip(_ columns: Range<Int>) {
        let width = 900, viewport = 360
        let run = capture(positions: [0, 50]) { position in
            rgbImage(width: width, height: viewport) { x, y in
                if columns.contains(x) { return band(position + y + x) }
                return (UInt8(30 + (y / 20) % 8 * 12), UInt8(40 + (x % 9) * 8), 70)
            }
        }
        precondition(run.ending == .success && run.image?.height == 410 && run.image?.width == width,
                     "the moving strip at \(columns) joins beside static columns: \(run.ending)")
        let expected = rgbImage(width: 1, height: 410) { _, y in band(y + columns.lowerBound) }
        let kept = run.image!.cropping(to: CGRect(x: columns.lowerBound, y: 0, width: 1, height: 410))!
        precondition(rgba(kept) == rgba(expected),
                     "the moving strip at \(columns) has every row")
    }

    /// Defect 1: grey alone matched a frame 256 rows (5,120 px) further down and joined it.
    static func wideJump() {
        let page = Page(width: 1_837, viewport: 1_400)
        let jumped = capture(positions: Array(stride(from: 0, to: 5_740, by: 160)) + [5_740, 10_880], frame: page.frame)
        precondition(jumped.ending == .partial, "a frame past the reach of the last one ends partial: \(jumped.ending)")
        let kept = seamless(jumped.image, "a wide area that lost the page")
        precondition(kept.last == (5_740 + 1_400 - 1) / 20, "it keeps every row up to the last joined frame")

        let guarded = capture(positions: Array(stride(from: 0, through: 15_000, by: 1_000)), frame: page.frame)
        precondition(guarded.ending == .limitedByGuard && guarded.image?.height == 25_000_000 / 1_837,
                     "a wide area runs to the pixel guard: \(guarded.ending), \(guarded.image?.height ?? -1) px")
        _ = seamless(guarded.image, "a wide area up to the guard")
    }

    /// Defect 2: a slow gradient read as a fixed footer, so the cap's last strip left a gap before it.
    static func heightCap() {
        let page = Page(width: 256, viewport: 1_300)
        let capped = capture(positions: [0, 20] + Array(stride(from: 180, through: 21_000, by: 160)), frame: page.frame)
        precondition(capped.ending == .limitedByHeight && capped.image?.height == 20_000,
                     "the cap ends at exactly 20,000 px: \(capped.ending), \(capped.image?.height ?? -1) px")
        precondition(seamless(capped.image, "a run to the cap").count == 1_000, "every row to the end")
    }

    /// Defect 3: grey rows a few px apart look alike, so a small step joined 1-3 px off.
    static func stickyBands() {
        let page = Page(width: 256, viewport: 1_300, stickyRows: 60)
        var positions = [0]
        for step in [13, 90, 7, 33, 10, 61, 3, 120, 18, 47, 11, 140, 9, 26, 77, 5, 38, 130, 14, 59] {
            positions.append(positions.last! + step)
        }
        for step in [40, 25, 80, 15] { positions.append(positions.last! - step) }
        for step in [52, 29, 145, 12, 66, 31, 101, 8, 44] { positions.append(positions.last! + step) }
        let run = capture(positions: positions, frame: page.frame)
        precondition(run.ending == .success, "a sticky page joins: \(run.ending)")
        let bands = rows(run.image!).map(\.row)
        precondition(bands.first == .header && bands.last == .footer
                     && bands.filter { $0 == .header || $0 == .footer }.count == 2,
                     "the header shows once at the top and the footer once at the bottom")
        _ = seamless(run.image, "a sticky page, down, up and down", firstRow: 3)
    }
}
