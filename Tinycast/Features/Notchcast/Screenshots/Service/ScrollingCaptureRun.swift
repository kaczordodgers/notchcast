// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18d's scrolling capture: the polling loop, the finish flag and cancellation.

import CoreGraphics
import Foundation
import Synchronization

/// Finish, asked on the main actor and read by the loop between frames.
final class ScrollingFinishFlag: Sendable {
    private let requested = Mutex(false)

    func request() { requested.withLock { $0 = true } }

    var isRequested: Bool { requested.withLock { $0 } }
}

/// Watches the area by its pixels alone while it is scrolled, so wheel, keys and scroll bars count.
enum ScrollingCaptureRun {
    struct Result: Sendable {
        let image: CGImage
        let ending: ScrollStitchSession.Ending
    }

    /// Throws `CancellationError` when cancelled, and a capture failure when no picture came of it.
    @concurrent
    static func run(
        _ source: ScreenshotRegionSource, finish: ScrollingFinishFlag, uptime: @escaping @Sendable () -> TimeInterval,
        pause: @escaping @Sendable (TimeInterval) async throws -> Void,
        progress: @escaping @MainActor @Sendable (Int) -> Void
    ) async throws -> Result {
        let first = await source.image()
        try Task.checkCancellation()
        guard let first, var session = ScrollStitchSession(first: first, at: uptime()) else {
            throw ScreenshotRequest.Failure.encodingFailed
        }
        await progress(session.height)
        while true {
            try Task.checkCancellation()
            switch session.next(at: uptime(), finishRequested: finish.isRequested) {
            case .wait(let seconds):
                try await pause(seconds)
            case .capture:
                let frame = await source.image()
                try Task.checkCancellation()
                let height = session.height
                if let ending = session.take(frame, at: uptime()) { return try result(of: &session, ending) }
                if session.height != height { await progress(session.height) }
            case .end(let ending):
                return try result(of: &session, ending)
            }
        }
    }

    private static func result(of session: inout ScrollStitchSession, _ ending: ScrollStitchSession.Ending) throws
        -> Result {
        let image = ending == .failed ? nil : session.stitched()
        try Task.checkCancellation()
        guard let image else { throw ScreenshotRequest.Failure.encodingFailed }
        return Result(image: image, ending: ending)
    }
}
