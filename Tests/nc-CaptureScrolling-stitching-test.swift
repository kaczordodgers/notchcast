import CoreGraphics
import Foundation
import ImageIO

@main
struct CaptureScrollingTests {
    static func image(_ rows: [Int], width: Int = 8) -> CGImage {
        let pixels = rows.flatMap { row in
            (0..<width).flatMap { column -> [UInt8] in
                [UInt8(row & 255), UInt8((row >> 8) & 255), UInt8(column * 17), 255]
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data), let image = CGImage(
            width: width, height: rows.count, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ) else { fatalError("Could not create fixture") }
        return image
    }

    static func hashes(_ image: CGImage) -> [UInt64] {
        guard let hashes = ScrollingRowHashes.make(image) else { fatalError("Could not hash fixture") }
        return hashes
    }

    static func stitcher(_ rows: [Int], limit: Int = ScrollingStitcher.maximumHeight) -> ScrollingStitcher {
        let first = image(rows)
        guard let stitcher = ScrollingStitcher(first: first, hashes: hashes(first), limit: limit) else {
            fatalError("Could not create stitcher")
        }
        return stitcher
    }

    static func add(_ rows: [Int], to stitcher: inout ScrollingStitcher) -> ScrollingStitcher.Update {
        let frame = image(rows)
        return stitcher.add(frame, hashes: hashes(frame))
    }

    static func expectImage(_ stitcher: ScrollingStitcher, rows: [Int]) {
        guard let output = stitcher.image() else { fatalError("Missing stitched image") }
        precondition(output.height == rows.count, "Expected \(rows.count) rows, got \(output.height)")
        precondition(hashes(output) == hashes(image(rows)), "Stitched pixels or row order differ")
    }

    static func overlapTests() {
        for (header, footer) in [(24, 0), (0, 20), (24, 20)] {
            let prefix = Array(1000..<1000 + header)
            let suffix = Array(2000..<2000 + footer)
            let count = 200 - header - footer
            var sticky = stitcher(prefix + Array(0..<count) + suffix)
            precondition(add(prefix + Array(40..<count + 40) + suffix, to: &sticky) == .added(40))
            precondition(add(prefix + Array(80..<count + 80) + suffix, to: &sticky) == .added(40))
            expectImage(sticky, rows: Array(0..<count + 80))
        }
        var joined = stitcher(Array(0..<100))
        precondition(add(Array(40..<140), to: &joined) == .added(40))
        precondition(add(Array(80..<180), to: &joined) == .added(40))
        expectImage(joined, rows: Array(0..<180))
        precondition(add(Array(80..<180), to: &joined) == .unchanged)
        precondition(add(Array(20..<120), to: &joined) == .unchanged)
        precondition(add(Array(500..<600), to: &joined) == .unmatched)
        precondition(joined.height == 180)
        precondition(add(Array(120..<220), to: &joined) == .added(40))
        expectImage(joined, rows: Array(0..<220))

        var threshold = stitcher(Array(0..<100))
        var frame = Array(50..<150)
        for index in [1, 11, 21, 31, 41] { frame[index] += 1000 }
        precondition(add(frame, to: &threshold) == .added(50), "Exactly 9/10 must match")
        expectImage(threshold, rows: Array(0..<150))
        var rejected = stitcher(Array(0..<100))
        frame[45] += 1000
        precondition(add(frame, to: &rejected) == .unmatched, "Below 9/10 must be rejected")
        var changedAnchors = stitcher(Array(0..<100))
        var changed = Array(50..<150)
        for index in [0, 12, 24, 36, 48] { changed[index] += 1000 }
        precondition(add(changed, to: &changedAnchors) == .added(50),
                     "Changed rows must not hide a valid 9/10 overlap from anchor selection")
        expectImage(changedAnchors, rows: Array(0..<150))

        var tooLittle = stitcher(Array(0..<100))
        precondition(add(Array(90..<190), to: &tooLittle) == .unmatched)
        let wrongWidth = image(Array(50..<150), width: 4)
        precondition(tooLittle.add(wrongWidth, hashes: hashes(wrongWidth)) == .unmatched)
        precondition(tooLittle.add(image(Array(50..<150)), hashes: []) == .unmatched)
        var tiny = stitcher([1, 2, 3])
        precondition(add([1, 2, 3], to: &tiny) == .unchanged)
    }

    static func stickyEvidenceTests() {
        let margin = Array(repeating: 7, count: 25)
        var topMargin = stitcher(Array(margin[..<20]) + Array(0..<80))
        precondition(add(Array(margin[..<15]) + Array(0..<85), to: &topMargin) == .added(5))
        expectImage(topMargin, rows: Array(margin[..<20]) + Array(0..<85))
        var bottomMargin = stitcher(Array(0..<80) + Array(margin[..<20]))
        precondition(add(Array(5..<80) + margin, to: &bottomMargin) == .added(5))
        expectImage(bottomMargin, rows: Array(0..<80) + margin)

        var transient = stitcher(Array(0..<100))
        precondition(add(Array(0..<20) + Array(500..<580), to: &transient) == .unmatched)
        precondition(add(Array(40..<140), to: &transient) == .added(40))
        expectImage(transient, rows: Array(0..<140))

        let page = Array(repeating: 7, count: 100) + Array(1000..<1600)
        let header = Array(repeating: 7, count: 80)
        var flatHeader = stitcher(header + Array(page[0..<320]))
        for offset in stride(from: 30, through: 210, by: 30) {
            precondition(add(header + Array(page[offset..<offset + 320]), to: &flatHeader) == .added(30),
                         "A flat header over a same-colour margin must be cropped once the margin scrolls out")
        }
        expectImage(flatHeader, rows: Array(page[0..<530]))
        let strip = Array(repeating: 9, count: 15)
        let body = Array(repeating: 9, count: 10) + Array(0..<300)
        var flatStrip = stitcher(strip + Array(body[0..<85]))
        for (offset, added) in [(5, 5), (15, 10), (40, 25), (60, 20)] {
            precondition(add(strip + Array(body[offset..<offset + 85]), to: &flatStrip) == .added(added))
        }
        expectImage(flatStrip, rows: Array(body[0..<145]))
    }

    static func repeatedRowsTests() {
        var blank = stitcher(Array(repeating: 7, count: 100))
        precondition(add(Array(repeating: 7, count: 100), to: &blank) == .unchanged)
        precondition(add(Array(repeating: 8, count: 100), to: &blank) == .unmatched)
        var pattern = Array(repeating: 7, count: 200)
        for row in stride(from: 0, to: 200, by: 5) { pattern[row] = row + 100 }
        var joined = stitcher(Array(pattern[0..<100]))
        precondition(add(Array(pattern[50..<150]), to: &joined) == .added(50))
        expectImage(joined, rows: Array(pattern[0..<150]))

        var log = ScrollingRowLog()
        log.append([1, 2, 3, 1, 2, 3][...])
        precondition(log.placement(of: [1, 2, 3], minimumOverlap: 3) == 0,
                     "Equally good repeated placements must add the least content")
    }

    static func limitTests() {
        var limited = stitcher(Array(0..<100), limit: 125)
        precondition(add(Array(50..<150), to: &limited) == .limitReached)
        precondition(limited.height == 125 && limited.limitReached)
        expectImage(limited, rows: Array(0..<125))
        precondition(add(Array(75..<175), to: &limited) == .limitReached)
        var exact = stitcher(Array(0..<100), limit: 150)
        precondition(add(Array(50..<150), to: &exact) == .limitReached)
        let huge = stitcher(Array(0..<20_010), limit: 30_000)
        precondition(huge.height == 20_000 && huge.limitReached)
        expectImage(huge, rows: Array(0..<20_000))
        let first = image([1])
        precondition(ScrollingStitcher(first: first, hashes: hashes(first), limit: 0) == nil)
    }

    static func cadenceAndGeometryTests() {
        precondition(ScrollingCaptureCadence.interval(unchangedFor: 0) == 0.2)
        precondition(ScrollingCaptureCadence.interval(unchangedFor: 29.999) == 0.2)
        precondition(ScrollingCaptureCadence.interval(unchangedFor: 30) == 1)
        precondition(ScrollingCaptureCadence.interval(unchangedFor: 300) == 1)
        let display = CGRect(x: -1440, y: -400, width: 1440, height: 900)
        let rect = CGRect(x: -1400, y: -350, width: 200, height: 300)
        let local = ScrollingScreenSource.localRect(rect, displayFrame: display)
        precondition(local == CGRect(x: 40, y: 50, width: 200, height: 300))
        precondition(ScrollingScreenSource.localRect(.zero, displayFrame: display) == nil)
        precondition(ScrollingScreenSource.localRect(CGRect(x: -1500, y: 0, width: 200, height: 100),
                                                    displayFrame: display) == nil)
        precondition(ScrollingScreenSource.localRect(.infinite, displayFrame: display) == nil)
    }

    @MainActor
    static func waitUntil(_ predicate: () -> Bool) async {
        while !predicate() {
            await Task.yield()
        }
    }

    @MainActor
    static func sessionTests() async throws {
        let rect = CGRect(x: 0, y: 0, width: 8, height: 100)
        let fixture = image(Array(0..<100))
        let session = ScrollingCaptureSession(prepareCapture: { _, _, _ in { fixture } }, requestAccess: { true })
        try session.start(rect: rect, displayID: 1)
        await waitUntil { session.height == 100 }
        do {
            try session.start(rect: rect, displayID: 1)
            preconditionFailure("Duplicate start must fail")
        } catch ScrollingCaptureSession.Failure.alreadyRunning {}
        let result = try await session.stop()
        precondition(session.state == .stopped && result?.height == 100)
        guard let result else { fatalError("Stop lost captured frame") }
        let png = try await ScrollingCaptureSession.pngData(for: result)
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Invalid PNG") }
        precondition(hashes(decoded) == hashes(fixture))
        session.cancel()
        precondition(session.state == .idle && session.result == nil && session.height == 0)

        let denied = ScrollingCaptureSession(prepareCapture: { _, _, _ in
            preconditionFailure("Permission denial must not capture")
        }, requestAccess: { false })
        do {
            try denied.start(rect: rect, displayID: 1)
            preconditionFailure("Missing permission must fail")
        } catch ScrollingCaptureSession.Failure.permissionDenied {}
        do {
            try denied.start(rect: .zero, displayID: 1)
            preconditionFailure("Empty rect must fail")
        } catch ScrollingCaptureSession.Failure.invalidRect {}

        let failed = ScrollingCaptureSession(prepareCapture: { _, _, _ in
            throw ScrollingCaptureSession.Failure.displayUnavailable
        }, requestAccess: { true })
        try failed.start(rect: rect, displayID: 1)
        await waitUntil { failed.state == .failed }
        do {
            _ = try await failed.stop()
            preconditionFailure("Capture error must reach caller")
        } catch ScrollingCaptureSession.Failure.displayUnavailable {}

        let tall = image(Array(0..<20_010))
        let capped = ScrollingCaptureSession(prepareCapture: { _, _, _ in { tall } }, requestAccess: { true })
        try capped.start(rect: rect, displayID: 1)
        await waitUntil { capped.result != nil }
        precondition(capped.state == .limitReached && capped.height == 20_000)
        let cappedResult = try await capped.stop()
        precondition(cappedResult?.height == 20_000)
        try await replacementTests(rect: rect)
    }

    @MainActor
    final class PendingFrames {
        var pending: [CheckedContinuation<CGImage, Never>] = []
        var returned = 0
        var preparations = 0

        func prepare() -> ScrollingCaptureSession.CaptureFrame {
            preparations += 1
            return { await self.next() }
        }

        func next() async -> CGImage {
            let image = await withCheckedContinuation { pending.append($0) }
            returned += 1
            return image
        }
    }

    @MainActor
    static func replacementTests(rect: CGRect) async throws {
        let frames = PendingFrames()
        let session = ScrollingCaptureSession(prepareCapture: { _, _, _ in
            await frames.prepare()
        }, requestAccess: { true })
        try session.start(rect: rect, displayID: 1)
        await waitUntil { frames.pending.count == 1 }
        let obsolete = frames.pending.removeFirst()
        session.cancel()
        try session.start(rect: rect, displayID: 2)
        await waitUntil { frames.pending.count == 1 }
        let latest = image(Array(1000..<1100))
        frames.pending.removeFirst().resume(returning: latest)
        await waitUntil { session.height == 100 }
        await waitUntil { frames.pending.count == 1 }
        precondition(frames.preparations == 2, "Each session must prepare once across multiple frames")
        frames.pending.removeFirst().resume(returning: latest)
        await waitUntil { frames.returned == 2 }
        let output = try await session.stop()
        precondition(output.map(hashes) == hashes(latest))
        obsolete.resume(returning: image(Array(0..<100)))
        await waitUntil { frames.returned == 3 }
        precondition(session.state == .stopped && session.result.map(hashes) == hashes(latest),
                     "A cancelled capture must not replace the next session's result")
    }

    @MainActor
    static func main() async throws {
        overlapTests()
        stickyEvidenceTests()
        repeatedRowsTests()
        limitTests()
        cadenceAndGeometryTests()
        try await sessionTests()
        print("CaptureScrolling: stitching, repeated rows, 90% overlap, cap, cadence, geometry and session checks passed")
    }
}
