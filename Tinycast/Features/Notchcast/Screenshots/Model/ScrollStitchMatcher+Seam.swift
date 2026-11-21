// SPDX-License-Identifier: GPL-3.0-or-later

// Copyright (C) 2026 Vorssaint

extension ScrollStitchMatcher {
    struct ColourSample: Equatable, Sendable {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        var isValid: Bool { width > 0 && height > 0 && pixels.count == width * height * 4 }
    }

    static func verifiedOverlap(previous: ColourSample, current: ColourSample, overlap: Int,
                                fixedBottomRows: Int, contentColumns: [Int]) -> Int? {
        guard previous.isValid, current.isValid, previous.width == current.width,
            previous.height == current.height, fixedBottomRows >= 0,
            !contentColumns.isEmpty, contentColumns.allSatisfy({ (0..<previous.width).contains($0) })
        else { return nil }
        let height = previous.height, rowBytes = previous.width * 4
        let contentBytes = contentColumns.map { $0 * 4 }
        let limit = contentColumns.count * 3 * seamTolerance
        var scored: [(overlap: Int, mismatches: Int)] = []
        previous.pixels.withUnsafeBufferPointer { lhs in
            current.pixels.withUnsafeBufferPointer { rhs in
                for candidate in (overlap - 4)...(overlap + 4) where candidate > fixedBottomRows && candidate < height {
                    let seamEnd = candidate - fixedBottomRows
                    var mismatches = 0, clean = true
                    for row in stride(from: seamEnd - 1, through: max(0, seamEnd - 256), by: -1) {
                        let left = (row + height - candidate) * rowBytes, right = row * rowBytes
                        var error = 0
                        for byte in contentBytes {
                            error += abs(Int(lhs[left + byte]) - Int(rhs[right + byte]))
                            error += abs(Int(lhs[left + byte + 1]) - Int(rhs[right + byte + 1]))
                            error += abs(Int(lhs[left + byte + 2]) - Int(rhs[right + byte + 2]))
                        }
                        guard error > limit else { continue }
                        mismatches += 1
                        if row >= seamEnd - 32 { clean = false; break }
                    }
                    if clean { scored.append((candidate, mismatches)) }
                }
            }
        }
        guard let best = scored.min(by: { $0.mismatches < $1.mismatches }) else { return nil }
        if scored.allSatisfy({ $0.mismatches == 0 }), scored.contains(where: { $0.overlap == overlap }) {
            return overlap
        }
        guard !scored.contains(where: { $0.overlap != best.overlap && $0.mismatches == best.mismatches })
        else { return nil }
        return best.overlap
    }

    private static let seamTolerance = 3
}
