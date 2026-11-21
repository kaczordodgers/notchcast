// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18d's scrolling capture loop: its timings, guards and kept strips.

import CoreGraphics
import Foundation

/// One scrolling capture, fed frames with the uptime each was taken at; it keeps only their new rows.
struct ScrollStitchSession {
    /// The result never passes `height`, nor `pixels` in all (4 bytes each, so under 100 MB).
    struct Limits: Equatable, Sendable {
        var height = 20_000
        var pixels = 25_000_000
        var frames = 512
        var duration: TimeInterval = 120

        func height(forWidth width: Int) -> Int { width > 0 ? min(height, pixels / width) : 0 }
    }

    enum Ending: Equatable, Sendable { case success, partial, limitedByHeight, limitedByGuard, failed }

    enum Step: Equatable, Sendable {
        case capture
        case wait(TimeInterval)
        case end(Ending)
    }

    static let sampleInterval: TimeInterval = 0.09
    static let settleInterval: TimeInterval = 0.22
    /// After Finish, one last frame is taken; a page still moving gets this long to come to rest.
    static let finishGrace: TimeInterval = 0.85

    let limits: Limits
    /// Rows the result has so far, the fixed footer included.
    private(set) var height: Int
    private var strips: [CGImage]
    private var footer: CGImage?
    private var previousSample: ScrollStitchMatcher.Sample
    private var previousColour: ScrollStitchMatcher.ColourSample
    private var lastObservedSample: ScrollStitchMatcher.Sample
    private var contentSampleColumns: Range<Int>?
    private var contentPixelColumns: Range<Int>?
    private var fixedBottomPixels = 0
    private var hasUnmatchedContent = false
    private let startedAt: TimeInterval
    private var lastChangedAt: TimeInterval
    private var lastCaptureAt: TimeInterval
    private var scrollPending = false
    private var finishRequestedAt: TimeInterval?

    /// Nil when the first frame holds no picture.
    init?(first frame: CGImage, at uptime: TimeInterval, limits: Limits = Limits()) {
        guard let first = ScrollStitchImage.content(frame), let sample = ScrollStitchImage.sample(first),
            let colour = ScrollStitchImage.colourSample(first)
        else { return nil }
        self.limits = limits
        height = first.height
        strips = [first]
        previousSample = sample
        previousColour = colour
        lastObservedSample = sample
        startedAt = uptime
        lastChangedAt = uptime
        lastCaptureAt = uptime
    }

    mutating func next(at now: TimeInterval, finishRequested: Bool) -> Step {
        if finishRequested, finishRequestedAt == nil {
            finishRequestedAt = now
            // One last frame, even when nothing moved since the previous one.
            scrollPending = true
        }
        if let finishRequestedAt, !scrollPending || now - finishRequestedAt >= Self.finishGrace {
            return .end(hasUnmatchedContent ? .partial : .success)
        }
        if now - startedAt >= limits.duration || strips.count >= limits.frames { return .end(.limitedByGuard) }
        let sinceLastCapture = now - lastCaptureAt
        return sinceLastCapture < Self.sampleInterval ? .wait(Self.sampleInterval - sinceLastCapture) : .capture
    }

    /// Nil to go on; a frame that did not arrive keeps what was joined before it.
    mutating func take(_ frame: CGImage?, at uptime: TimeInterval) -> Ending? {
        guard let frame, let current = ScrollStitchImage.content(frame),
            let currentSample = ScrollStitchImage.sample(current)
        else { return .partial }
        lastCaptureAt = uptime
        let isStill = ScrollStitchMatcher.isStill(lastObservedSample, currentSample,
                                                  contentColumns: contentSampleColumns)
        lastObservedSample = currentSample
        if !isStill { lastChangedAt = uptime }
        switch ScrollStitchMatcher.transition(previous: previousSample, current: currentSample,
                                              contentColumns: contentSampleColumns) {
        case .end:
            hasUnmatchedContent = false
        case .advanced(let overlap, .forward, let columns):
            guard let colour = ScrollStitchImage.colourSample(current) else { return .partial }
            switch advance(to: current, sample: currentSample, colour: colour, sampleOverlap: overlap,
                           columns: columns) {
            case .joined: break
            case .unverified: hasUnmatchedContent = true
            case .ended(let ending): return ending
            }
        case .advanced(_, .backward, _):
            break
        case .unmatched:
            hasUnmatchedContent = true
        }
        scrollPending = !isStill || uptime - lastChangedAt < Self.settleInterval
        return nil
    }

    /// The joined picture; the strips are let go as they are drawn, so the session holds none after.
    mutating func stitched() -> CGImage? {
        var all = strips + (footer.map { [$0] } ?? [])
        strips = []
        footer = nil
        return ScrollStitchImage.stitch(&all)
    }

    private enum Advance { case joined, unverified, ended(Ending) }

    private mutating func advance(
        to current: CGImage, sample: ScrollStitchMatcher.Sample, colour: ScrollStitchMatcher.ColourSample,
        sampleOverlap matchedOverlap: Int, columns: [Int]
    ) -> Advance {
        let establishing = contentSampleColumns == nil
        let fixedRows = establishing
            ? ScrollStitchMatcher.fixedBottomRows(previous: previousSample, current: sample, overlap: matchedOverlap,
                                                  contentColumns: columns)
            : Int((Double(fixedBottomPixels) / Double(current.height) * Double(sample.height)).rounded())
        guard let sampleOverlap = ScrollStitchMatcher.verifiedOverlap(
            previous: previousColour, current: colour, overlap: matchedOverlap, fixedBottomRows: fixedRows,
            contentColumns: columns)
        else { return .unverified }
        let overlap = Int((Double(sampleOverlap) / Double(sample.height) * Double(current.height)).rounded())
        guard overlap > 0, overlap < current.height else { return .ended(.failed) }
        if establishing {
            // The matched columns only prove movement; every selected column is kept.
            let pixelColumns = 0..<current.width
            fixedBottomPixels = Int((Double(fixedRows) / Double(sample.height) * Double(current.height)).rounded())
            guard let firstColumn = columns.first, let lastColumn = columns.last,
                let revealed = ScrollStitchMatcher.newContentRows(
                imageHeight: current.height, overlap: overlap, fixedBottomRows: fixedBottomPixels),
                let first = ScrollStitchImage.strip(of: strips[0], columns: pixelColumns, topCrop: 0,
                                                    bottomCrop: fixedBottomPixels)
            else { return .ended(.failed) }
            contentSampleColumns = firstColumn..<(lastColumn + 1)
            contentPixelColumns = pixelColumns
            strips[0] = first
            if fixedBottomPixels > 0 {
                guard let kept = ScrollStitchImage.strip(of: current, columns: pixelColumns,
                                                         topCrop: revealed.upperBound, bottomCrop: 0)
                else { return .ended(.failed) }
                footer = kept
            }
        }
        guard let pixelColumns = contentPixelColumns, !pixelColumns.isEmpty,
            let revealed = ScrollStitchMatcher.newContentRows(
                imageHeight: current.height, overlap: overlap, fixedBottomRows: fixedBottomPixels)
        else { return .ended(.failed) }
        let allowed = limits.height(forWidth: pixelColumns.count)
        let room = allowed - height
        let reachesLimit = revealed.count >= room
        let limit: Ending = allowed == limits.height ? .limitedByHeight : .limitedByGuard
        guard room > 0 else { return .ended(limit) }
        let rows = revealed.lowerBound..<(revealed.lowerBound + min(revealed.count, room))
        guard let strip = ScrollStitchImage.strip(of: current, columns: pixelColumns, topCrop: rows.lowerBound,
                                                  bottomCrop: current.height - rows.upperBound)
        else { return .ended(.failed) }
        if fixedBottomPixels > 0, !establishing {
            guard let kept = ScrollStitchImage.strip(of: current, columns: pixelColumns,
                                                     topCrop: current.height - fixedBottomPixels, bottomCrop: 0)
            else { return .ended(.failed) }
            footer = kept
        }
        strips.append(strip)
        height += rows.count
        previousSample = sample
        previousColour = colour
        hasUnmatchedContent = false
        return reachesLimit ? .ended(limit) : .joined
    }
}
