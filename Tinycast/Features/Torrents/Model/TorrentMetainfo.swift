import Foundation

struct TorrentMetainfo: Sendable {
    let info: Data
    let name: String

    static func read(_ data: Data) throws -> Self {
        var parser = Parser(bytes: Array(data))
        guard parser.take() == 100 else { throw TorrentFailure.invalidTorrent }
        var info: Data?
        var name: String?
        var keys = Set<Data>()
        while parser.peek != 101 {
            let key = try parser.string()
            guard keys.insert(key).inserted else { throw TorrentFailure.invalidTorrent }
            if key == Data("info".utf8) {
                let start = parser.offset
                name = try parser.infoName()
                info = Data(parser.bytes[start..<parser.offset])
            } else {
                try parser.skip(depth: 0)
            }
        }
        _ = parser.take()
        guard parser.offset == parser.bytes.count, let info, let name, !name.isEmpty else {
            throw TorrentFailure.invalidTorrent
        }
        return Self(info: info, name: name)
    }

    static func magnetHash(_ url: URL) throws -> String {
        guard url.scheme?.lowercased() == "magnet",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw TorrentFailure.invalidInput
        }
        let hashes = (components.queryItems ?? []).filter { $0.name.lowercased() == "xt" }.compactMap { item -> String? in
            guard let value = item.value, value.lowercased().hasPrefix("urn:btih:") else { return nil }
            return String(value.dropFirst(9)).uppercased()
        }
        guard hashes.count == 1, let hash = hashes.first else { throw TorrentFailure.invalidInput }
        if hash.utf8.count == 40, hash.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) {
            return hash.lowercased()
        }
        guard hash.utf8.count == 32 else { throw TorrentFailure.invalidInput }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        var buffer: UInt32 = 0
        var bits = 0
        var bytes: [UInt8] = []
        for character in hash.utf8 {
            guard let value = alphabet.firstIndex(of: character) else { throw TorrentFailure.invalidInput }
            buffer = (buffer << 5) | UInt32(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                bytes.append(UInt8((buffer >> bits) & 255))
            }
        }
        return WebRules.hex(bytes)
    }

    private struct Parser {
        let bytes: [UInt8]
        var offset = 0
        var peek: UInt8? { offset < bytes.count ? bytes[offset] : nil }

        mutating func take() -> UInt8? {
            guard let value = peek else { return nil }
            offset += 1
            return value
        }

        mutating func string() throws -> Data {
            let start = offset
            while let byte = peek, (48...57).contains(byte) { offset += 1 }
            guard offset > start, offset - start < 10,
                  offset - start == 1 || bytes[start] != 48,
                  let digits = String(bytes: bytes[start..<offset], encoding: .ascii), let length = Int(digits),
                  take() == 58, length <= bytes.count - offset else { throw TorrentFailure.invalidTorrent }
            defer { offset += length }
            return Data(bytes[offset..<(offset + length)])
        }

        mutating func infoName() throws -> String? {
            guard take() == 100 else { throw TorrentFailure.invalidTorrent }
            var name: String?
            var utf8Name: String?
            var keys = Set<Data>()
            while peek != 101 {
                let key = try string()
                guard keys.insert(key).inserted else { throw TorrentFailure.invalidTorrent }
                if key == Data("name".utf8) {
                    name = String(data: try string(), encoding: .utf8)
                } else if key == Data("name.utf-8".utf8) {
                    utf8Name = String(data: try string(), encoding: .utf8)
                } else {
                    try skip(depth: 0)
                }
            }
            _ = take()
            return utf8Name ?? name
        }

        mutating func skip(depth: Int) throws {
            guard depth < 64, let byte = peek else { throw TorrentFailure.invalidTorrent }
            switch byte {
            case 100, 108:
                _ = take()
                var keys = Set<Data>()
                while peek != 101 {
                    if byte == 100 {
                        guard keys.insert(try string()).inserted else { throw TorrentFailure.invalidTorrent }
                    }
                    try skip(depth: depth + 1)
                }
                _ = take()
            case 105:
                _ = take()
                let start = offset
                while let digit = peek, digit != 101 { offset += 1 }
                let number = String(bytes: bytes[start..<offset], encoding: .ascii)
                guard take() == 101, let number, Int64(number) != nil, number != "-0",
                      number == "0" || (!number.hasPrefix("0") && !number.hasPrefix("-0")) else {
                    throw TorrentFailure.invalidTorrent
                }
            case 48...57:
                _ = try string()
            default:
                throw TorrentFailure.invalidTorrent
            }
        }
    }
}
