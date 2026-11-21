import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Synchronization

// The shipped `live` and settings UI are left out: these stand in, so `makeModule` runs as shipped.

struct ScreenshotsSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "nc-Screenshots.\(UUID())")
let downloadsFolder = scratch.appending(path: "Downloads")
let chosenFolder = scratch.appending(path: "Chosen")
let fixedDate = Date(timeIntervalSince1970: 1_763_290_800)

/// A scrolled page's viewport, `offset` rows down a document no two rows of which repeat nearby.
func page(offset: Int, seed: UInt32 = 0) -> CGImage {
    let width = 32, height = 120
    var pixels = [UInt8](repeating: 0, count: width * height)
    for row in 0..<height {
        for column in 0..<width {
            var value = UInt32((row + offset) * width + column) &+ seed
            value = (value ^ (value >> 16)) &* 0x45d9f3b
            pixels[row * width + column] = UInt8(truncatingIfNeeded: value ^ (value >> 13))
        }
    }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                   space: CGColorSpaceCreateDeviceGray(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                   provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: false,
                   intent: .defaultIntent)!
}

/// The run's uptime in whole microseconds, moved only by its pauses and frames, so a wait ends.
final class FakeClock: Sendable {
    private let micros = Mutex(0)

    var now: TimeInterval { Double(micros.withLock { $0 }) / 1_000_000 }

    func advance(_ by: TimeInterval) { micros.withLock { $0 += max(1, Int((by * 1_000_000).rounded(.up))) } }
}

let clock = FakeClock()

func image(width: Int, height: Int) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

@MainActor
final class ScreenshotFake {
    var granted = true
    var holdFreeze = false
    var freezeGate: CheckedContinuation<Void, Never>?
    var freezes: [(point: CGPoint?, exclusion: ScreenshotExclusion)] = []
    var displays = [
        ScreenshotFrozenDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 50),
                                image: image(width: 200, height: 100)),
        ScreenshotFrozenDisplay(id: 2, frame: CGRect(x: 100, y: 0, width: 100, height: 50),
                                image: image(width: 100, height: 50)),
    ]
    var windows: [ScreenshotWindow] = []
    var cursor = CGPoint(x: 150, y: 10)
    var frozenWindows: [[UInt32]] = []
    var windowWidth = 30
    var closedWindows: Set<UInt32> = []
    var clipboardWorks = true
    var clipboard: [Data] = []
    var surfaces: [(displays: [UInt32], windows: [UInt32])] = []
    var answer: (@MainActor (ScreenshotRequest?) -> Void)?
    var closes = 0
    var lines: [ScreenTextLine] = []
    var recognizedWidths: [Int] = []
    var textWorks = true
    var texts: [String] = []
    var settingsOpened = 0
    var holdRecognize = false
    var recognizeFails = false
    var recognizeGate: CheckedContinuation<Void, Never>?
    var holdWarm = false
    var warmGate: CheckedContinuation<Void, Never>?
    var warmOffMain: [Bool] = []
    var warmCancelled: [Bool] = []
    var frames: [CGImage?] = []
    var served = 0
    var holdFrames = true
    var frameSeconds = 0.01
    var frameGate: CheckedContinuation<Void, Never>?
    var regions: [ScrollingCaptureRegion] = []
    var regionFails = false
    var guides = 0
    var hiddenGuides = 0
    var edited: [CGImage] = []

    /// Once `frames` are served it waits for the test, so the run stands still while it is checked.
    func frame() async -> CGImage? {
        if served >= frames.count, holdFrames { await withCheckedContinuation { frameGate = $0 } }
        defer { served += 1 }
        clock.advance(frameSeconds)
        return frames.isEmpty ? nil : frames[min(served, frames.count - 1)]
    }

    func releaseFrames(holding: Bool = false) {
        holdFrames = holding
        let gate = frameGate
        frameGate = nil
        gate?.resume()
    }

    func scroll(_ frames: [CGImage?]) {
        self.frames = frames
        served = 0
        holdFrames = true
    }

    struct VisionFailed: Error {}

    func recognize(_ image: CGImage) async throws -> [ScreenTextLine] {
        recognizedWidths.append(image.width)
        if holdRecognize { await withCheckedContinuation { recognizeGate = $0 } }
        if recognizeFails { throw VisionFailed() }
        return lines
    }

    func warm(offMain: Bool) async {
        warmOffMain.append(offMain)
        if holdWarm { await withCheckedContinuation { warmGate = $0 } }
    }

    func releaseWarm() {
        warmGate?.resume()
        warmGate = nil
    }

    func releaseRecognize() {
        recognizeGate?.resume()
        recognizeGate = nil
    }

    func release() {
        freezeGate?.resume()
        freezeGate = nil
    }

    func pick(_ request: ScreenshotRequest?) {
        let answer = answer
        self.answer = nil
        answer?(request)
    }
}

@MainActor let fake = ScreenshotFake()

extension ScreenshotSystem {
    static let live = ScreenshotSystem(
        grantAccess: { fake.granted },
        freeze: { point, exclusion in
            fake.freezes.append((point, exclusion))
            if fake.holdFreeze { await withCheckedContinuation { fake.freezeGate = $0 } }
            return fake.displays.filter { display in point.map(display.frame.contains) ?? true }
        },
        windows: { fake.windows },
        freezeWindows: { ids in
            fake.frozenWindows.append(ids)
            return Dictionary(uniqueKeysWithValues: ids.filter { !fake.closedWindows.contains($0) }
                .map { ($0, image(width: fake.windowWidth, height: 20)) })
        },
        cursor: { fake.cursor },
        writeClipboard: { data in
            guard fake.clipboardWorks else { return false }
            fake.clipboard.append(data)
            return true
        },
        writeText: { text in
            guard fake.textWorks else { return false }
            fake.texts.append(text)
            return true
        },
        recognizeText: { image in try await fake.recognize(image) },
        warmTextRecognition: {
            let offMain = pthread_main_np() == 0
            await fake.warm(offMain: offMain)
            let cancelled = Task.isCancelled
            await MainActor.run { fake.warmCancelled.append(cancelled) }
        },
        openScreenRecordingSettings: { fake.settingsOpened += 1 },
        downloads: { downloadsFolder },
        chooseSaveFile: { _ in nil },
        select: { frozen, windows, completion in
            fake.surfaces.append((frozen.map(\.id), windows.map(\.id)))
            fake.answer = completion
            return {
                fake.closes += 1
                fake.pick(nil)
            }
        },
        edit: { image, _, _ in
            fake.edited.append(image)
            return {}
        },
        openRegion: { region in
            fake.regions.append(region)
            if fake.regionFails { throw ScreenshotRequest.Failure.targetUnavailable }
            return ScreenshotRegionSource { await fake.frame() }
        },
        uptime: { clock.now },
        pause: { seconds in
            clock.advance(seconds)
            await Task.yield()
        },
        showGuide: { _ in
            fake.guides += 1
            return { fake.hiddenGuides += 1 }
        }
    )
}

@MainActor
final class FakePresenter: IslandPresenting {
    var posts: [IslandNotice] = []
    var events: [String] = []

    func showLevel(_ level: IslandLevel) {}
    func post(_ notice: IslandNotice, onTap: (@MainActor () -> Void)?) {
        posts.append(notice)
        events.append("post " + notice.id)
    }
    func end(notice id: String) { events.append("end " + id) }
    var status: IslandStatus?
    var statusTap: (@MainActor () -> Void)?
    var rows: [IslandMenuRow] = []
    var select: (@MainActor (String) -> Void)?
    func setStatus(_ status: IslandStatus?, for id: String, onTap: (@MainActor () -> Void)?) {
        precondition(status == nil || status?.id == id, "a status is set under its own id")
        self.status = status
        statusTap = onTap
    }
    func setMenuRows(_ rows: [IslandMenuRow], owner: String, onSelect: @escaping @MainActor (String) -> Void) {
        precondition(owner == "screenshot.scrolling", "only the scrolling capture has menu rows")
        self.rows = rows
        select = onSelect
    }
}

@MainActor
final class Rig {
    let suite = "nc-Screenshots-test.\(UUID())"
    let defaults: UserDefaults
    let presenter = FakePresenter()
    let controller: NotchcastController

    init() {
        defaults = UserDefaults(suiteName: suite)!
        let hub = NotchcastTapHub(syntheticTag: 0x54494E59, isTrusted: { true }, makeSession: { _ in
            fatalError("Screenshots declares no tap")
        })
        controller = NotchcastController(
            addons: [ScreenshotsAddon.self], defaults: defaults, hub: hub, dictation: FakeDictation(),
            presenter: presenter, now: { fixedDate })
        controller.start()
    }

    func fire(_ id: String) {
        precondition(controller.run(entryID: id), "\(id) resolves")
    }

    func finish() {
        controller.stop()
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

let area = "command:nc-screenshot-area"
let display = "command:nc-screenshot-display"
let editLast = "command:nc-edit-last-screenshot"
let text = "command:nc-capture-text"
let scroll = "command:nc-scrolling-capture"

func drain() async { try? await Task.sleep(for: .milliseconds(120)) }

/// Yields the main actor until the condition holds; no clock, so a hang fails by the cap instead.
@MainActor
func settle(_ what: String, tries: Int = 100_000, until condition: @MainActor () -> Bool) async {
    for _ in 0..<tries {
        if condition() { return }
        await Task.yield()
    }
    preconditionFailure("never settled: \(what)")
}

let recognizing = IslandNotice(
    id: "screenshot.text", symbol: "text.viewfinder", text: "Recognizing text…", progress: IslandProgress(fraction: nil))

func files(in folder: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
}

func isPNG(_ data: Data?) -> Bool { data?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) }

func pngDPI(_ data: Data?) -> Double? {
    data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        .flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }?[kCGImagePropertyDPIWidth] as? Double
}

func pngHeight(_ data: Data?) -> Int? {
    data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.height
}

func pngWidth(_ data: Data?) -> Int? {
    data.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
        .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }?.width
}
