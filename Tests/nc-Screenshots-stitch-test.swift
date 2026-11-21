// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18d's scrolling capture tests: the generated frames and their cases.
// notchcast-sources: -O Tinycast/Features/Notchcast/Screenshots/Model/*.swift

import CoreGraphics
import CoreText
import Foundation

// #938: the stitching, driven frame by frame with made-up uptimes: no capture, no sleep.

typealias Session = ScrollStitchSession

func grey(width: Int, height: Int, _ bytes: [UInt8]) -> CGImage {
    CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)!
}

func frame(offset: Int, width: Int = 32, height: Int = 120, seed: Int = 0, contentWidth: Int? = nil,
           sparse: Bool = false) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height)
    for row in 0..<height {
        for column in 0..<(contentWidth ?? width) {
            let r = row + offset
            if seed == 0 {
                pixels[row * width + column] = UInt8((r * 17 + column * 31 + (r / 7) * 13) % 251)
            } else {
                var value = UInt32(r * width + column + seed)
                value = (value ^ (value >> 16)) &* 0x45d9f3b
                value = (value ^ (value >> 16)) &* 0x45d9f3b
                pixels[row * width + column] = UInt8(truncatingIfNeeded: value ^ (value >> 16))
            }
            if sparse {
                // Text-like rows between white bands: random pixels alone hide false matches on blank space.
                pixels[row * width + column] = r % 24 < 8 ? 215 + pixels[row * width + column] % 40 : 255
            }
        }
    }
    return grey(width: width, height: height, pixels)
}

/// The document stands still; only a banner's rows change.
func stationaryPage(animationOffset: Int, blankBackground: Bool = false, bannerRows: Range<Int> = 30..<66) -> CGImage {
    let width = 32, height = 120
    var bytes = blankBackground ? [UInt8](repeating: 255, count: width * height) : greyBytes(frame(offset: 0, seed: 91))
    let animated = greyBytes(frame(offset: animationOffset, seed: 91))
    for row in bannerRows {
        bytes.replaceSubrange(row * width..<(row + 1) * width, with: animated[row * width..<(row + 1) * width])
    }
    return grey(width: width, height: height, bytes)
}

/// A transparent bottom row and right column, as ScreenCaptureKit pads an area.
func paddedFrame(offset: Int) -> CGImage {
    let image = frame(offset: offset)
    let context = CGContext(data: nil, width: image.width + 1, height: image.height + 1, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 1, width: image.width, height: image.height))
    return context.makeImage()!
}

/// A fixed 20-row header over sparse lines.
func sparsePage(offset: Int, height: Int = 120) -> CGImage {
    let width = 32
    var bytes = [UInt8](repeating: 255, count: width * height)
    for row in 0..<height {
        let documentRow = row < 20 ? row : row + offset
        guard row < 20 || [26, 49, 74, 97, 117, 141].contains(documentRow) else { continue }
        for column in 0..<width { bytes[row * width + column] = UInt8((documentRow * 17 + column * 31) % 181) }
    }
    return grey(width: width, height: height, bytes)
}

/// `frame(offset:)` with its last `footer` rows covered by a footer that never scrolls.
func footerPage(offset: Int, height: Int = 120, footer: Int = 16, contentRows: Int? = nil) -> CGImage {
    let width = 32
    let body = contentRows ?? height - footer
    var bytes = greyBytes(frame(offset: offset, height: body))
    for row in 0..<footer {
        bytes += (0..<width).map { UInt8((row * 29 + $0 * 7) % 97 + 120) }
    }
    return grey(width: width, height: body + footer, bytes)
}

func greyBytes(_ image: CGImage) -> [UInt8] { Array(image.dataProvider!.data! as Data) }

func pixels(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return bytes
}

/// Sparse, repeated numbered lines 1,800 px wide, drawn once so viewports are crops of one document.
func terminalDocument() -> CGImage {
    let width = 1_800, height = 150 * 28
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateUIFontForLanguage(.userFixedPitch, 24, nil)!
    for line in 1...150 {
        let text = NSAttributedString(string: String(line), attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ])
        context.textPosition = CGPoint(x: 12, y: height - line * 28 + 8)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
    }
    return context.makeImage()!
}

/// 251 distinct noise rows, so any window under 251 rows is unique; a row is copied, not computed.
struct RowBank {
    let width: Int
    let rows: [[UInt8]]

    init(width: Int) {
        self.width = width
        rows = (0..<251).map { row in
            (0..<width).map { column in
                var value = UInt32(row * 7_919 + column * 104_729 + 17)
                value = (value ^ (value >> 16)) &* 0x45d9f3b
                return UInt8(truncatingIfNeeded: value ^ (value >> 13))
            }
        }
    }

    func frame(offset: Int, height: Int = 120) -> CGImage {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height)
        for row in offset..<(offset + height) { bytes += rows[row % rows.count] }
        return grey(width: width, height: height, bytes)
    }
}

struct Run {
    let ending: Session.Ending
    let image: CGImage?
    let heights: [Int]
    let captures: Int
}

/// The run's loop on a microsecond clock: `frames`, then the last again; Finish after `finishAfter`.
func capture(_ frames: [CGImage?], limits: Session.Limits = Session.Limits(), finishAfter: Int? = nil) -> Run {
    let finishAfter = finishAfter ?? frames.count
    var micros = 0
    var now: TimeInterval { Double(micros) / 1_000_000 }
    guard let first = frames.first.flatMap({ $0 }), var session = Session(first: first, at: now, limits: limits) else {
        return Run(ending: .failed, image: nil, heights: [], captures: 1)
    }
    var served = 1
    var heights = [session.height]
    var ending: Session.Ending?
    for _ in 0..<100_000 where ending == nil {
        switch session.next(at: now, finishRequested: served >= finishAfter) {
        case .wait(let seconds):
            precondition(seconds > 0, "a wait is never zero")
            micros += max(1, Int((seconds * 1_000_000).rounded(.up)))
        case .capture:
            let image = frames[min(served, frames.count - 1)]
            served += 1
            micros += 10_000
            let before = session.height
            ending = session.take(image, at: now)
            if session.height != before { heights.append(session.height) }
        case .end(let end):
            ending = end
        }
    }
    guard let ending else { preconditionFailure("the session never ended") }
    let image = ending == .failed ? nil : session.stitched()
    precondition(session.stitched() == nil, "the session lets go of its strips once stitched")
    return Run(ending: ending, image: image, heights: heights, captures: served)
}

/// A look every 0.1 s at `offset(tick)`, Finish from `finishTick`; answers the tick it ended on.
func timed(finishTick: Int, offset: (Int) -> Int) -> (ending: Session.Ending, tick: Int, image: CGImage?) {
    var session = Session(first: frame(offset: offset(0)), at: 0)!
    for tick in 1...100 {
        let now = Double(tick) / 10
        switch session.next(at: now, finishRequested: tick >= finishTick) {
        case .capture:
            if let ending = session.take(frame(offset: offset(tick)), at: now) {
                return (ending, tick, session.stitched())
            }
        case .wait: continue
        case .end(let ending): return (ending, tick, session.stitched())
        }
    }
    preconditionFailure("the timed session never ended")
}

func expect(_ run: Run, _ ending: Session.Ending, _ what: String, matches expected: CGImage? = nil,
            height: Int? = nil) {
    precondition(run.ending == ending, "\(what): ended \(run.ending), expected \(ending)")
    if let height { precondition(run.image?.height == height, "\(what): \(run.image?.height ?? -1) rows, not \(height)") }
    if let expected {
        precondition(run.image.map(pixels) == pixels(expected),
                     "\(what): pixels differ (\(run.image?.width ?? -1)×\(run.image?.height ?? -1))")
    }
}

@main
enum ScrollStitchTests {
    static func main() {
        stitching()
        matching()
        sessions()
        limits()
        finishing()
        phases()
        regions()
        print("nc-Screenshots-stitch-test: ok")
    }

    static func stitching() {
        let heights = [1522, 160, 240, 320, 720, 400, 80, 1120, 400, 400, 78]
        var strips = heights.map { height -> CGImage in
            let context = CGContext(data: nil, width: 2876, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 2876, height: height))
            return context.makeImage()!
        }
        guard let joined = ScrollStitchImage.stitch(&strips) else { preconditionFailure("tall strips join") }
        var alpha = [UInt8](repeating: 0, count: joined.height)
        let context = CGContext(data: &alpha, width: 1, height: joined.height, bitsPerComponent: 8, bytesPerRow: 1,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
        context.draw(joined, in: CGRect(x: 0, y: 0, width: 1, height: joined.height))
        precondition(joined.height == 5440 && alpha.allSatisfy { $0 == 255 },
                     "tall Retina strips stitch with no transparent seam rows")
        precondition(strips.isEmpty, "the stitch lets go of every strip it drew")
    }

    static func matching() {
        func sample(_ image: CGImage) -> ScrollStitchMatcher.Sample {
            ScrollStitchMatcher.Sample(width: image.width, height: image.height, pixels: greyBytes(image))
        }
        let start = sample(frame(offset: 0, width: 256, height: 1340, seed: 91))
        let next = sample(frame(offset: 83, width: 256, height: 1340, seed: 91))
        let clock = ContinuousClock()
        var transition = ScrollStitchMatcher.Transition.unmatched
        let elapsed = clock.measure {
            transition = ScrollStitchMatcher.transition(previous: start, current: next)
        }
        guard case .advanced(1257, .forward, let columns) = transition else {
            preconditionFailure("Retina-height matching answers the exact native-pixel overlap: \(transition)")
        }
        precondition(columns.count == 32 && Set(columns.map { $0 / 32 }).count == 8,
                     "the wide matcher selects 32 columns across the moving area")
        // Reported, never asserted: a wall-clock bound flakes on a loaded runner.
        print("nc-Screenshots-stitch-test: Retina match took \(elapsed)")
        precondition(ScrollStitchMatcher.newContentRows(imageHeight: 120, overlap: 78, fixedBottomRows: 16)
                     == 62..<104, "a fixed footer shifts the revealed rows up by its height")
        precondition(ScrollStitchMatcher.newContentRows(imageHeight: 120, overlap: 78, fixedBottomRows: 78) == nil,
                     "a footer taller than the overlap is no footer")
    }

    static func sessions() {
        expect(capture([0, 12, 24, 36].map { stationaryPage(animationOffset: $0) }), .success,
               "a still page with an animated banner adds no rows", height: 120)
        expect(capture([frame(offset: 0), frame(offset: 42)]), .success,
               "two frames join exactly", matches: frame(offset: 0, height: 162))
        expect(capture([frame(offset: 0), frame(offset: 42), frame(offset: 72)]), .success,
               "three frames join exactly", matches: frame(offset: 0, height: 192))
        expect(capture([frame(offset: 0), frame(offset: 42)], finishAfter: 1), .success,
               "Finish takes one last frame", matches: frame(offset: 0, height: 162))
        expect(capture([frame(offset: 0)]), .success, "Finish with no scrolling returns the first frame",
               matches: frame(offset: 0))
        expect(capture([0, 42, 84, 180, 276, 372, 468, 564, 660].map { frame(offset: $0, seed: 91) }), .success,
               "a long page keeps every row after a near-viewport advance",
               matches: frame(offset: 0, height: 780, seed: 91))
        expect(capture([0, 8, 94, 180, 266, 352, 438, 524, 610].map { frame(offset: $0, seed: 91, sparse: true) }),
               .success, "white bands never turn a forward scroll into backtracking",
               matches: frame(offset: 0, height: 730, seed: 91, sparse: true))
        let sparse = capture([0, 12, 24, 36].map { sparsePage(offset: $0) })
        expect(sparse, .success, "a fixed header shows once, over every sparse row",
               matches: sparsePage(offset: 0, height: 156))
        precondition(sparse.heights == [120, 132, 144, 156], "the height grows by each scroll: \(sparse.heights)")

        let terminal = terminalDocument()
        let regular = stride(from: 0, through: 120, by: 15).map {
            terminal.cropping(to: CGRect(x: 0, y: $0 * 28, width: terminal.width, height: 30 * 28))!
        }
        expect(capture(regular), .success, "repeated terminal lines join with none missing or doubled",
               matches: terminal)
        let irregular = [0, 211, 87, 587, 1_000, 1_400].map {
            terminal.cropping(to: CGRect(x: 0, y: $0, width: terminal.width, height: 30 * 28))!
        }
        expect(capture(irregular), .success, "irregular steps and backtracking keep exact alignment",
               matches: terminal.cropping(to: CGRect(x: 0, y: 0, width: terminal.width, height: 2_240))!)

        expect(capture([frame(offset: 0), frame(offset: 42), frame(offset: 12), frame(offset: 72)]), .success,
               "scrolling back then forward never doubles a row", matches: frame(offset: 0, height: 192))
        expect(capture([frame(offset: 0), frame(offset: 42), frame(offset: 12)]), .success,
               "Finish right after scrolling back keeps the furthest rows", matches: frame(offset: 0, height: 162))
        expect(capture([frame(offset: 0, contentWidth: 8), frame(offset: 42, contentWidth: 8)]), .success,
               "a narrow moving column keeps the blank side", matches: frame(offset: 0, height: 162, contentWidth: 8))
        expect(capture([paddedFrame(offset: 0), paddedFrame(offset: 42), paddedFrame(offset: 72)]), .success,
               "transparent padded edges leave no seam", matches: frame(offset: 0, height: 192))
        expect(capture([footerPage(offset: 0), footerPage(offset: 42), footerPage(offset: 72)]), .success,
               "a fixed footer shows once, at the end", matches: footerPage(offset: 0, contentRows: 176))

        expect(capture([frame(offset: 0), frame(offset: 0, seed: 91)]), .partial,
               "an unrelated second frame keeps the first", matches: frame(offset: 0))
        expect(capture([frame(offset: 0, seed: 91, sparse: true), frame(offset: 104, seed: 731, sparse: true)]),
               .partial, "white space alone joins nothing", height: 120)
        expect(capture([frame(offset: 0), frame(offset: 42), frame(offset: 0, seed: 91)]), .partial,
               "a later mismatch keeps everything joined before it", matches: frame(offset: 0, height: 162))
        expect(capture([frame(offset: 0), nil]), .partial, "a frame that fails later keeps what came before",
               matches: frame(offset: 0))
        expect(capture([nil]), .failed, "no first frame fails")
    }

    static func limits() {
        let standard = Session.Limits()
        precondition(standard.height == 20_000 && standard.pixels == 25_000_000 && standard.frames == 512
                     && standard.duration == 120, "the issue's cap, the 100 MB guard and Vorssaint's guards")
        precondition(standard.height(forWidth: 1_250) == 20_000 && standard.height(forWidth: 1_251) == 19_984
                     && standard.height(forWidth: 1_400) == 17_857 && standard.height(forWidth: 3_456) == 7_233,
                     "the pixel guard ends a wide area before 20,000 px")
        precondition(standard.height(forWidth: 1_251) * 1_251 * 4 < 100_000_000, "the result stays under 100 MB")

        let steps = (0..<250).map { frame(offset: $0 * 100) }
        let capped = capture(steps)
        expect(capped, .limitedByHeight, "a run that would pass 20,000 px ends at exactly 20,000",
               matches: frame(offset: 0, height: 20_000))
        precondition(capped.captures < steps.count, "the run ends by itself, before Finish")

        let footed = capture((0..<400).map { footerPage(offset: $0 * 60) })
        expect(footed, .limitedByHeight, "the cap counts the fixed footer, which still ends the image",
               matches: footerPage(offset: 0, contentRows: 19_984))

        for (width, ending, height) in [(1_250, Session.Ending.limitedByHeight, 20_000),
                                        (1_251, .limitedByGuard, 19_984)] {
            let bank = RowBank(width: width)
            let run = capture((0..<250).map { bank.frame(offset: $0 * 100) })
            expect(run, ending, "a \(width) px wide area ends by \(ending)", height: height)
            precondition(run.image.map { $0.width * $0.height <= standard.pixels } == true,
                         "a \(width) px wide result keeps under the pixel guard")
        }

        expect(capture((0..<10).map { frame(offset: $0 * 10) }, limits: Session.Limits(frames: 3)), .limitedByGuard,
               "the strip guard ends the run", matches: frame(offset: 0, height: 140))
        expect(capture((0..<10).map { frame(offset: $0 * 10) }, limits: Session.Limits(duration: 0.25)),
               .limitedByGuard, "the time guard ends the run", matches: frame(offset: 0, height: 140))
    }

    static func finishing() {
        let settling = timed(finishTick: 2) { min($0, 3) * 10 }
        precondition(settling.ending == .success && settling.tick == 7,
                     "Finish waits until the page is still for 0.22 s: \(settling.ending) at tick \(settling.tick)")
        precondition(settling.image.map(pixels) == pixels(frame(offset: 0, height: 150)),
                     "rows that arrive after Finish are kept")
        let moving = timed(finishTick: 2) { $0 * 10 }
        precondition(moving.ending == .success && moving.tick == 11,
                     "a page that never stops ends 0.85 s after Finish: \(moving.ending) at tick \(moving.tick)")
        precondition(moving.image.map(pixels) == pixels(frame(offset: 0, height: 220)),
                     "a page that never stops keeps every row until the grace ends")
    }

    static func phases() {
        precondition([ScrollingCapturePhase.idle, .selecting, .capturing, .finishing].map(\.command)
                     == [.start, .ignore, .finish, .ignore],
                     "the command starts, finishes while capturing, and is ignored while selecting or finishing")
        let texts = [0, 999, 1_000, 1_250, 9_999, 10_000, 19_999, 20_000].map(ScrollingCapturePhase.heightText)
        precondition(texts == ["0", "999", "1k", "1.2k", "9.9k", "10k", "19k", "20k"], "height texts: \(texts)")
        precondition(texts.allSatisfy { $0.count <= 4 }, "the pill shows at most four characters")
    }

    static func regions() {
        let pixels = { (width: Int, height: Int) in
            grey(width: width, height: height, [UInt8](repeating: 0, count: width * height))
        }
        let displays = [
            ScreenshotFrozenDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 50), image: pixels(200, 100)),
            ScreenshotFrozenDisplay(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 50), image: pixels(100, 50)),
        ]
        let windows = [ScreenshotWindow(id: 7, ownerPID: 9, frame: CGRect(x: 110, y: 5, width: 40, height: 30)),
                       ScreenshotWindow(id: 8, ownerPID: 9, frame: CGRect(x: 90, y: 5, width: 40, height: 30))]
        let dragged = ScrollingCaptureRegion(.rect(CGRect(x: 10.2, y: 10.3, width: 20, height: 10)),
                                             displays: displays, windows: windows)
        precondition(dragged == nil ? false : dragged!.displayID == 1 && dragged!.scale == 2
                     && dragged!.rect == CGRect(x: 10, y: 10, width: 20.5, height: 10.5),
                     "a dragged area snaps outward to whole Retina pixels: \(String(describing: dragged))")
        precondition(ScrollingCaptureRegion(.window(7), displays: displays, windows: windows)
                     == ScrollingCaptureRegion(.rect(CGRect(x: 110, y: 5, width: 40, height: 30)),
                                               displays: displays, windows: windows),
                     "a clicked window becomes its frame")
        precondition(ScrollingCaptureRegion(.display(2), displays: displays, windows: windows)?.rect
                     == displays[1].frame, "Return takes the whole display")
        precondition(ScrollingCaptureRegion(.window(8), displays: displays, windows: windows) == nil
                     && ScrollingCaptureRegion(.rect(CGRect(x: 90, y: 5, width: 20, height: 5)), displays: displays,
                                               windows: windows) == nil,
                     "an area across two displays is unavailable")
        precondition(ScrollingCaptureRegion(.rect(CGRect(x: 10, y: 10, width: 0, height: 5)), displays: displays,
                                            windows: windows) == nil
                     && ScrollingCaptureRegion(.window(99), displays: displays, windows: windows) == nil,
                     "an empty area or a gone window is unavailable")
    }
}
