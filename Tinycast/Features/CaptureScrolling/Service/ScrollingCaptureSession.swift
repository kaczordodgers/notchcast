import CoreGraphics
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class ScrollingCaptureSession {
    enum State: Equatable {
        case idle, capturing, stopping, stopped, limitReached, failed
    }

    enum Failure: CaptureFailureConvertible {
        case alreadyRunning, permissionDenied, invalidRect, displayUnavailable, invalidFrame
        case imageCreationFailed, pngEncodingFailed

        var captureFailure: CaptureFailure? {
            switch self {
            case .permissionDenied: .permissionDenied
            case .invalidRect, .displayUnavailable: .areaUnavailable
            case .alreadyRunning, .invalidFrame, .imageCreationFailed, .pngEncodingFailed: .captureFailed
            }
        }
    }

    typealias CaptureFrame = @MainActor @Sendable () async throws -> CGImage
    typealias PrepareCapture = @Sendable (CGRect, CGDirectDisplayID, Set<CGWindowID>) async throws -> CaptureFrame

    private(set) var state = State.idle
    private(set) var height = 0
    private(set) var lastUpdate = ScrollingStitcher.Update.unchanged
    private(set) var result: CGImage?
    private(set) var failure: (any Error)?
    @ObservationIgnored private var task: Task<CGImage?, any Error>?
    @ObservationIgnored private var operationID = UUID()
    @ObservationIgnored private let prepareCapture: PrepareCapture
    @ObservationIgnored private let requestAccess: () -> Bool

    init(
        prepareCapture: @escaping PrepareCapture = ScrollingScreenSource.prepare,
        requestAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() }
    ) {
        self.prepareCapture = prepareCapture
        self.requestAccess = requestAccess
    }

    deinit { task?.cancel() }

    func start(rect: CGRect, displayID: CGDirectDisplayID, excludingWindows: Set<CGWindowID> = []) throws {
        guard task == nil else { throw Failure.alreadyRunning }
        guard !rect.isNull, !rect.isInfinite, rect.width > 0, rect.height > 0,
              rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else {
            throw Failure.invalidRect
        }
        guard requestAccess() else { throw Failure.permissionDenied }
        let id = UUID()
        operationID = id
        state = .capturing
        height = 0
        lastUpdate = .unchanged
        result = nil
        failure = nil
        let prepareCapture = prepareCapture
        task = Task { [weak self] in
            do {
                let image = try await Self.collect(rect: rect, displayID: displayID, excludingWindows: excludingWindows,
                                                   prepareCapture: prepareCapture) { [weak self] height, update in
                    guard let self, self.operationID == id else { return }
                    self.height = height
                    self.lastUpdate = update
                    if update == .limitReached { self.state = .limitReached }
                }
                guard let self, self.operationID == id else { return nil }
                self.result = image
                if self.state != .limitReached { self.state = .stopped }
                self.task = nil
                return image
            } catch {
                guard let self, self.operationID == id else { return nil }
                self.failure = error
                self.state = .failed
                self.task = nil
                throw error
            }
        }
    }

    func stop() async throws -> CGImage? {
        guard let task else {
            if let failure { throw failure }
            return result
        }
        if state != .limitReached { state = .stopping }
        task.cancel()
        return try await task.value
    }

    func cancel() {
        operationID = UUID()
        task?.cancel()
        task = nil
        state = .idle
        height = 0
        result = nil
        failure = nil
    }

    @concurrent
    static func pngData(for image: CGImage) async throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw Failure.pngEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw Failure.pngEncodingFailed }
        return data as Data
    }

    @concurrent
    private static func collect(
        rect: CGRect, displayID: CGDirectDisplayID, excludingWindows: Set<CGWindowID>, prepareCapture: PrepareCapture,
        progress: @MainActor @Sendable (Int, ScrollingStitcher.Update) -> Void
    ) async throws -> CGImage? {
        let clock = ContinuousClock()
        var changedAt = clock.now
        var previous: [UInt64] = []
        var stitcher: ScrollingStitcher?
        do {
            let capture = try await prepareCapture(rect, displayID, excludingWindows)
            try Task.checkCancellation()
            while !Task.isCancelled {
                let started = clock.now
                let image = try await capture()
                try Task.checkCancellation()
                guard let hashes = ScrollingRowHashes.make(image) else { throw Failure.invalidFrame }
                let update: ScrollingStitcher.Update
                if stitcher == nil {
                    stitcher = ScrollingStitcher(first: image, hashes: hashes)
                    guard let stitcher else { throw Failure.invalidFrame }
                    update = stitcher.limitReached ? .limitReached : .added(stitcher.height)
                } else {
                    update = stitcher?.add(image, hashes: hashes) ?? .unmatched
                }
                try Task.checkCancellation()
                if hashes != previous { changedAt = clock.now }
                previous = hashes
                await progress(stitcher?.height ?? 0, update)
                if update == .limitReached { break }
                let elapsed = changedAt.duration(to: clock.now).components
                let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18
                let interval = ScrollingCaptureCadence.interval(unchangedFor: seconds)
                try await clock.sleep(until: started.advanced(by: .seconds(interval)))
            }
        } catch {
            if !Task.isCancelled { throw error }
        }
        guard let stitcher else { return nil }
        guard let image = stitcher.image() else { throw Failure.imageCreationFailed }
        return image
    }
}
