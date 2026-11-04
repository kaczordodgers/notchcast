import CoreGraphics

enum ScrollingRowHashes {
    static func make(_ image: CGImage) -> [UInt64]? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return (0..<height).map { row in
            var hash: UInt64 = 0xcbf29ce484222325
            for pixel in 0..<width {
                for channel in 0..<3 {
                    hash = (hash ^ UInt64(pixels[row * bytesPerRow + pixel * 4 + channel])) &* 0x100000001b3
                }
            }
            return hash
        }
    }
}
