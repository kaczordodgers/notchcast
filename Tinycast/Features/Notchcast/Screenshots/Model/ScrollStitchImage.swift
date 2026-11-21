// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Adapted from Vorssaint faada18d's scrolling capture: edge trimming, the sample, strips and the stitch.

import CoreGraphics

/// The pixel work of a scrolling capture: what the matcher reads, and the strips it keeps and joins.
enum ScrollStitchImage {
    /// ScreenCaptureKit can pad an area with a transparent edge row, which would become a seam.
    static func content(_ image: CGImage) -> CGImage? {
        if [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo) { return image }
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        var alpha = [UInt8](repeating: 0, count: width * height)
        let drawn = alpha.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        func clearRow(_ row: Int) -> Bool { alpha[(row * width)..<((row + 1) * width)].allSatisfy { $0 == 0 } }
        var top = 0, bottom = height, left = 0, right = width
        while top < bottom && clearRow(top) { top += 1 }
        while bottom > top && clearRow(bottom - 1) { bottom -= 1 }
        guard top < bottom else { return nil }
        while left < right && (top..<bottom).allSatisfy({ alpha[$0 * width + left] == 0 }) { left += 1 }
        while right > left && (top..<bottom).allSatisfy({ alpha[$0 * width + right - 1] == 0 }) { right -= 1 }
        guard left < right else { return nil }
        if top == 0 && bottom == height && left == 0 && right == width { return image }
        return image.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top))
    }

    /// Native rows for exact offsets, and up to 256 columns so different digits stay apart.
    static func sample(_ image: CGImage) -> ScrollStitchMatcher.Sample? {
        let width = min(256, image.width)
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? ScrollStitchMatcher.Sample(width: width, height: height, pixels: pixels) : nil
    }

    /// `sample`'s columns in colour, for checking a join where grey rows look alike.
    static func colourSample(_ image: CGImage) -> ScrollStitchMatcher.ColourSample? {
        let width = min(256, image.width)
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? ScrollStitchMatcher.ColourSample(width: width, height: height, pixels: pixels) : nil
    }

    /// Drawn into its own bitmap, because a cropped image can keep its whole source frame alive.
    static func strip(of image: CGImage, columns: Range<Int>, topCrop: Int, bottomCrop: Int) -> CGImage? {
        let height = image.height - topCrop - bottomCrop
        guard image.width > 0, height > 0, topCrop >= 0, bottomCrop >= 0, columns.lowerBound >= 0,
            columns.upperBound <= image.width, !columns.isEmpty,
            let source = image.cropping(to: CGRect(x: columns.lowerBound, y: topCrop, width: columns.count,
                                                   height: height)),
            let context = bitmap(width: columns.count, height: height, like: image)
        else { return nil }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: columns.count, height: height))
        return context.makeImage()
    }

    /// Joins the strips top to bottom, letting go of each once it is drawn so only one copy grows.
    static func stitch(_ strips: inout [CGImage]) -> CGImage? {
        guard let first = strips.first else { return nil }
        guard strips.count > 1 else { return first }
        let width = strips.map(\.width).min() ?? first.width
        let height = strips.reduce(0) { $0 + $1.height }
        guard let context = bitmap(width: width, height: height, like: first) else { return nil }
        context.interpolationQuality = .none
        var destinationY = height
        strips.reverse()
        while let strip = strips.popLast() {
            guard !Task.isCancelled,
                let piece = strip.cropping(to: CGRect(x: 0, y: 0, width: width, height: strip.height))
            else { return nil }
            destinationY -= strip.height
            context.draw(piece, in: CGRect(x: 0, y: destinationY, width: piece.width, height: piece.height))
        }
        guard destinationY == 0 else { return nil }
        return context.makeImage()
    }

    /// The capture's own colour space, so a strip is never colour-matched on its way into the result.
    private static func bitmap(width: Int, height: Int, like image: CGImage) -> CGContext? {
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
