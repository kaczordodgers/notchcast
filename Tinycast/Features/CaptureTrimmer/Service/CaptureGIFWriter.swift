import Foundation
import ImageIO
import UniformTypeIdentifiers

final class CaptureGIFWriter {
    private let file: FileHandle
    private var started = false

    init(url: URL) throws {
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CaptureTrimService.Failure.cannotWrite
        }
        file = try FileHandle(forWritingTo: url)
    }

    func append(_ image: CGImage, delay: Double) throws {
        try autoreleasepool {
            let data = NSMutableData()
            guard let encoder = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 1, nil)
            else { throw CaptureTrimService.Failure.cannotWrite }
            CGImageDestinationAddImage(encoder, image, [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
            guard CGImageDestinationFinalize(encoder) else { throw CaptureTrimService.Failure.cannotWrite }
            try writeFrame(Data(referencing: data))
        }
    }

    private func writeFrame(_ data: Data) throws {
        guard data.count >= 14, data.last == 0x3B else { throw CaptureTrimService.Failure.cannotWrite }
        let flags = data[10]
        let paletteSize = flags & 0x80 == 0 ? 0 : 3 * (1 << (Int(flags & 7) + 1))
        guard data.count > 13 + paletteSize else { throw CaptureTrimService.Failure.cannotWrite }
        if !started {
            var header = Data("GIF89a".utf8)
            header.append(data[6..<13 + paletteSize])
            try file.write(contentsOf: header)
            try file.write(contentsOf: Data([0x21, 0xFF, 11]) + Data("NETSCAPE2.0".utf8)
                + Data([3, 1, 0, 0, 0]))
            started = true
        }
        var offset = 13 + paletteSize
        while offset < data.count, data[offset] == 0x21 {
            let begin = offset
            guard offset + 2 < data.count else { throw CaptureTrimService.Failure.cannotWrite }
            offset += 2
            while true {
                guard offset < data.count else { throw CaptureTrimService.Failure.cannotWrite }
                let length = Int(data[offset])
                offset += length + 1
                guard offset <= data.count else { throw CaptureTrimService.Failure.cannotWrite }
                if length == 0 { break }
            }
            try file.write(contentsOf: data[begin..<offset])
        }
        guard offset + 10 < data.count, data[offset] == 0x2C else {
            throw CaptureTrimService.Failure.cannotWrite
        }
        var descriptor = Data(data[offset..<offset + 10])
        let hasLocalPalette = descriptor[9] & 0x80 != 0
        if !hasLocalPalette, paletteSize > 0 {
            descriptor[9] = (descriptor[9] & 0x78) | 0x80 | (flags & 7)
        }
        try file.write(contentsOf: descriptor)
        if !hasLocalPalette, paletteSize > 0 { try file.write(contentsOf: data[13..<13 + paletteSize]) }
        try file.write(contentsOf: data[offset + 10..<data.count - 1])
    }

    func finish() throws {
        guard started else { throw CaptureTrimService.Failure.cannotWrite }
        try file.write(contentsOf: Data([0x3B]))
        try file.close()
    }
}
