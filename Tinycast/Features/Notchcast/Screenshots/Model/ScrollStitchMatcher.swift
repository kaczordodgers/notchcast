// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18d's screenshot support: the scrolling overlap search and its guards.

import Accelerate
import Foundation

/// How far two successive views of a scrolled area moved, judged on small greyscale samples.
enum ScrollStitchMatcher {
    struct Sample: Equatable, Sendable {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        var isValid: Bool { width > 0 && height > 0 && pixels.count == width * height }
    }

    enum Direction: Equatable, Sendable { case forward, backward }

    enum Transition: Equatable, Sendable {
        case end
        case advanced(overlap: Int, direction: Direction, contentColumns: [Int])
        case unmatched
    }

    static func isStill(_ previous: Sample, _ current: Sample, contentColumns: Range<Int>? = nil) -> Bool {
        guard previous.isValid, current.isValid, previous.width == current.width,
            previous.height == current.height else { return false }
        let columns = contentColumns ?? 0..<previous.width
        guard columns.lowerBound >= 0, columns.upperBound <= previous.width, !columns.isEmpty else { return false }
        // Empty space must not dilute movement in a narrow column of text.
        return tiles(in: columns, sampleWidth: previous.width).allSatisfy {
            difference(previous, current, columns: $0) <= 1.5
        }
    }

    /// The rows two successive views share; it never joins on a guess, so a doubt is `.unmatched`.
    static func transition(previous: Sample, current: Sample, contentColumns: Range<Int>? = nil) -> Transition {
        guard previous.isValid, current.isValid, previous.width == current.width,
            previous.height == current.height, previous.height >= 24 else { return .unmatched }
        let columns = contentColumns ?? 0..<previous.width
        guard columns.lowerBound >= 0, columns.upperBound <= previous.width, !columns.isEmpty else {
            return .unmatched
        }
        if isStill(previous, current, contentColumns: columns) { return .end }

        let height = previous.height
        let minimumAdvance = 2
        let maximumAdvance = min(height - 8, Int((Double(height) * 0.88).rounded()))
        guard minimumAdvance <= maximumAdvance else { return .unmatched }

        let tiles = tiles(in: columns, sampleWidth: previous.width)
        if previous.width > 32 { return compactTransition(previous, current, columns: columns, tiles: tiles) }
        let movingTiles = tiles.filter { difference(previous, current, columns: $0) > 1.5 }
        guard !movingTiles.isEmpty else { return .unmatched }

        let previousPixels = previous.pixels.map(Float.init)
        let currentPixels = current.pixels.map(Float.init)
        var differences = [Float](repeating: 0, count: previous.pixels.count)
        var matches: [Match] = []
        for advance in minimumAdvance...maximumAdvance {
            if Task.isCancelled { return .unmatched }
            for reversed in [false, true] {
                let count = (height - advance) * previous.width
                previousPixels.withUnsafeBufferPointer { lhs in
                    currentPixels.withUnsafeBufferPointer { rhs in
                        vDSP_vsub(rhs.baseAddress! + (reversed ? advance * previous.width : 0), 1,
                                  lhs.baseAddress! + (reversed ? 0 : advance * previous.width), 1,
                                  &differences, 1, vDSP_Length(count))
                    }
                }
                vDSP_vabs(differences, 1, &differences, 1, vDSP_Length(count))
                guard let candidate = candidate(previous: previous, advance: advance, tiles: movingTiles,
                                                differences: differences) else { continue }
                matches.append(Match(advance: advance, reversed: reversed, candidate: candidate))
            }
        }
        guard !matches.isEmpty else { return .unmatched }
        matches.sort {
            let lhs = $0.candidate, rhs = $1.candidate
            if lhs.contentColumns.count != rhs.contentColumns.count {
                return lhs.contentColumns.count > rhs.contentColumns.count
            }
            if lhs.supportingTiles != rhs.supportingTiles { return lhs.supportingTiles > rhs.supportingTiles }
            // Similar digits pass the row tolerance at a wrong offset; the closer match wins first.
            if lhs.difference != rhs.difference { return lhs.difference < rhs.difference }
            if lhs.longestRun != rhs.longestRun { return lhs.longestRun > rhs.longestRun }
            return lhs.matchingRows > rhs.matchingRows
        }

        let best = matches[0]
        let requiredRun = requiredRun(height: height)
        guard best.candidate.longestRun >= requiredRun else { return .unmatched }
        if matches.dropFirst().contains(where: { isRival($0, of: best, requiredRun: requiredRun) }) {
            return .unmatched
        }
        return motion(previous: best.reversed ? current : previous, current: best.reversed ? previous : current,
                      advance: best.advance, columns: best.candidate.contentColumns,
                      direction: best.reversed ? .backward : .forward)
    }

    /// Footer rows that stay put while the page behind them advances; they are kept once, at the end.
    static func fixedBottomRows(previous: Sample, current: Sample, overlap: Int, contentColumns: [Int]) -> Int {
        guard previous.isValid, current.isValid, previous.width == current.width,
            previous.height == current.height, overlap > 0, overlap < previous.height,
            !contentColumns.isEmpty, contentColumns.allSatisfy({ (0..<previous.width).contains($0) })
        else { return 0 }
        var rows = 0
        for row in stride(from: previous.height - 1, through: 0, by: -1) {
            let start = row * previous.width
            var difference = 0
            for column in contentColumns {
                difference += abs(Int(previous.pixels[start + column]) - Int(current.pixels[start + column]))
            }
            guard Double(difference) / Double(contentColumns.count) <= 2 else { break }
            rows += 1
        }
        // A slow gradient also barely changes in place; a row the scroll explains as well is not fixed.
        let advance = previous.height - overlap
        while rows > 0 {
            let row = previous.height - rows
            guard row >= advance else { break }
            var aligned = 0, shifted = 0
            for column in contentColumns {
                let pixel = Int(previous.pixels[row * previous.width + column])
                aligned += abs(pixel - Int(current.pixels[row * previous.width + column]))
                shifted += abs(pixel - Int(current.pixels[(row - advance) * previous.width + column]))
            }
            guard shifted <= aligned else { break }
            rows -= 1
        }
        let minimumRows = max(4, min(12, previous.height / 100))
        guard rows >= minimumRows, rows < overlap else { return 0 }
        return rows
    }

    /// Rows a forward scroll revealed; a fixed footer shifts them up by its own height.
    static func newContentRows(imageHeight: Int, overlap: Int, fixedBottomRows: Int) -> Range<Int>? {
        guard imageHeight > 0, overlap > 0, overlap < imageHeight, fixedBottomRows >= 0, fixedBottomRows < overlap
        else { return nil }
        return (overlap - fixedBottomRows)..<(imageHeight - fixedBottomRows)
    }

    private struct Match {
        let advance: Int
        let reversed: Bool
        let candidate: Candidate
    }

    private struct Candidate {
        let contentColumns: Range<Int>
        let supportingTiles: Int
        let longestRun: Int
        let matchingRows: Int
        let difference: Double
    }

    private struct RowMatch {
        let longestRun: Int
        let matchingRows: Int
        let comparedRows: Int
        let difference: Double
    }

    private static func requiredRun(height: Int) -> Int { max(8, min(28, height / 12)) }

    /// Repeated content can match as well at another offset; an equally precise, substantial rival vetoes.
    private static func isRival(_ rival: Match, of best: Match, requiredRun: Int) -> Bool {
        let lhs = rival.candidate, rhs = best.candidate
        // An approximate low-contrast pattern must not veto an exact overlap.
        let tolerance = min(0.75, rhs.difference)
        return (rival.reversed != best.reversed || abs(rival.advance - best.advance) > 2)
            && lhs.contentColumns.count >= rhs.contentColumns.count - 1
            && lhs.supportingTiles >= rhs.supportingTiles - 1
            && lhs.longestRun >= max(requiredRun, rhs.longestRun / 2)
            && lhs.matchingRows >= max(requiredRun, rhs.matchingRows / 2)
            && lhs.difference <= rhs.difference + tolerance
    }

    /// A wide sample searches only 32 of its most changing columns, so different digits stay apart.
    private static func compactTransition(
        _ previous: Sample, _ current: Sample, columns: Range<Int>, tiles: [Range<Int>]
    ) -> Transition {
        let selected: [Int]
        if columns.count <= 32 {
            selected = Array(columns)
        } else {
            let perTile = max(1, 32 / tiles.count)
            selected = tiles.flatMap { tile in
                tile.map { column in
                    (column: column, difference: difference(previous, current, columns: column..<(column + 1)))
                }.sorted {
                    if $0.difference != $1.difference { return $0.difference > $1.difference }
                    return $0.column < $1.column
                }.prefix(perTile).map(\.column).sorted()
            }
        }
        func compact(_ sample: Sample) -> Sample {
            var pixels = [UInt8]()
            pixels.reserveCapacity(selected.count * sample.height)
            for row in 0..<sample.height {
                let start = row * sample.width
                for column in selected { pixels.append(sample.pixels[start + column]) }
            }
            return Sample(width: selected.count, height: sample.height, pixels: pixels)
        }
        let found = transition(previous: compact(previous), current: compact(current))
        guard case .advanced(let overlap, let direction, let matched) = found else { return found }
        let movingColumns = matched.map { selected[$0] }.filter { column in
            difference(previous, current, columns: column..<(column + 1)) > 1.5
        }
        return .advanced(overlap: overlap, direction: direction, contentColumns: movingColumns)
    }

    /// Tells a real scroll from an animation: a scroll explains every changed row at its offset.
    private static func motion(previous: Sample, current: Sample, advance: Int, columns: Range<Int>,
                               direction: Direction) -> Transition {
        let overlap = previous.height - advance
        var firstChange = current.height, lastChange = -1
        var firstMoving = current.height, lastMoving = -1, moving = 0
        var stationaryRows: [Int] = []
        var unexplainedChange = false
        for row in 0..<current.height {
            var aligned = 0, shifted = 0
            for column in columns {
                let index = row * current.width + column
                let pixel = Int(current.pixels[index])
                aligned += abs(Int(previous.pixels[index]) - pixel)
                if row < overlap { shifted += abs(Int(previous.pixels[index + advance * previous.width]) - pixel) }
            }
            let alignedError = Double(aligned) / Double(columns.count)
            if alignedError > 1.5 {
                firstChange = min(firstChange, row)
                lastChange = row
            }
            guard row < overlap else { continue }
            let shiftedError = Double(shifted) / Double(columns.count)
            if shiftedError <= 8 && alignedError > shiftedError + 1.5 {
                firstMoving = min(firstMoving, row)
                lastMoving = row
                moving += 1
            } else if alignedError <= 1.5 && shiftedError > alignedError + 1.5 {
                stationaryRows.append(row)
            } else if alignedError > 1.5 && shiftedError > 8 {
                unexplainedChange = true
            }
        }
        guard moving > 0 else { return .unmatched }
        if lastChange - firstChange + 1 < current.height / 2 {
            // A banner moving between still document rows is not a scroll; a sparse line sliding intact is.
            if stationaryRows.count > moving, stationaryRows.contains(firstChange - 1),
                stationaryRows.contains(lastChange + 1) { return .end }
            if unexplainedChange || lastChange >= overlap { return .unmatched }
        }
        // A fixed header's texture must never outvote a few widely spaced lines of real text.
        let movingRegion = firstMoving...lastMoving
        guard stationaryRows.lazy.filter({ movingRegion.contains($0) }).count <= moving else { return .unmatched }
        return .advanced(overlap: overlap, direction: direction, contentColumns: Array(columns))
    }

    private static func difference(_ lhs: Sample, _ rhs: Sample, columns: Range<Int>) -> Double {
        guard columns.lowerBound >= 0, columns.upperBound <= lhs.width, !columns.isEmpty else { return .infinity }
        let topInset = max(0, lhs.height / 24)
        var difference = 0
        var count = 0
        for row in topInset..<(lhs.height - topInset) {
            let start = row * lhs.width
            for column in columns {
                difference += abs(Int(lhs.pixels[start + column]) - Int(rhs.pixels[start + column]))
                count += 1
            }
        }
        return count > 0 ? Double(difference) / Double(count) : .infinity
    }

    private static func tiles(in columns: Range<Int>, sampleWidth: Int) -> [Range<Int>] {
        let tileWidth = max(2, sampleWidth / 8)
        var tiles: [Range<Int>] = []
        var lower = columns.lowerBound
        while lower < columns.upperBound {
            let upper = min(columns.upperBound, lower + tileWidth)
            if upper - lower >= 2 || tiles.isEmpty { tiles.append(lower..<upper) }
            lower = upper
        }
        return tiles
    }

    private static func candidate(previous: Sample, advance: Int, tiles: [Range<Int>],
                                  differences: [Float]) -> Candidate? {
        let requiredRun = requiredRun(height: previous.height)
        func supported(_ columns: Range<Int>) -> RowMatch? {
            guard let match = rowMatch(previous: previous, advance: advance, columns: columns,
                                       differences: differences),
                match.longestRun >= requiredRun, match.matchingRows >= max(requiredRun, match.comparedRows / 3)
            else { return nil }
            return match
        }
        let matches = tiles.map { ($0, supported($0)) }
        let minimumTiles = matches.count >= 3 ? 2 : 1
        var runs: [[Range<Int>]] = []
        var run: [Range<Int>] = []
        var skippedOneTile = false
        for (tile, match) in matches {
            if match != nil {
                run.append(tile)
            } else if !run.isEmpty, !skippedOneTile {
                skippedOneTile = true
            } else {
                if !run.isEmpty { runs.append(run) }
                run = []
                skippedOneTile = false
            }
        }
        if !run.isEmpty { runs.append(run) }

        return runs.compactMap { tiles -> Candidate? in
            guard tiles.count >= minimumTiles, let first = tiles.first, let last = tiles.last else { return nil }
            let columns = first.lowerBound..<last.upperBound
            guard let combined = supported(columns) else { return nil }
            return Candidate(contentColumns: columns, supportingTiles: tiles.count, longestRun: combined.longestRun,
                             matchingRows: combined.matchingRows, difference: combined.difference)
        }.max {
            if $0.contentColumns.count != $1.contentColumns.count {
                return $0.contentColumns.count < $1.contentColumns.count
            }
            if $0.matchingRows != $1.matchingRows { return $0.matchingRows < $1.matchingRows }
            return $0.difference > $1.difference
        }
    }

    private static func rowMatch(previous: Sample, advance: Int, columns: Range<Int>,
                                 differences: [Float]) -> RowMatch? {
        let width = previous.width
        // Trim the shared rows, not the viewport: a viewport inset can erase a valid small overlap.
        let edgeInset = max(2, (previous.height - advance) / 10)
        let lastRow = previous.height - advance - edgeInset
        guard lastRow > edgeInset, columns.lowerBound >= 0, columns.upperBound <= width, !columns.isEmpty else {
            return nil
        }
        let rowCount = lastRow - edgeInset
        var rowDifferences = [Float](repeating: 0, count: rowCount)
        let weights = [Float](repeating: 1, count: columns.count)
        differences.withUnsafeBufferPointer { buffer in
            vDSP_desamp(buffer.baseAddress! + edgeInset * width + columns.lowerBound, vDSP_Stride(width), weights,
                        &rowDifferences, vDSP_Length(rowCount), vDSP_Length(columns.count))
        }
        var longestRun = 0, run = 0, matchingRows = 0
        var totalDifference: Float = 0
        let threshold = Float(columns.count * 8)
        // Indexing the array here took seconds per Retina frame in unoptimised Debug builds.
        rowDifferences.withUnsafeBufferPointer { rows in
            for row in 0..<rowCount {
                if rows[row] <= threshold {
                    totalDifference += rows[row]
                    run += 1
                    matchingRows += 1
                    longestRun = max(longestRun, run)
                } else {
                    // A changing block counts its capped error, never as a match.
                    totalDifference += threshold
                    run = 0
                }
            }
        }
        return RowMatch(longestRun: longestRun, matchingRows: matchingRows, comparedRows: rowCount,
                        difference: Double(totalDifference) / Double(rowCount * columns.count))
    }
}
