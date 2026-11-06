import Foundation

nonisolated enum ArchiveZIPEncoding {
    struct Inspection: Sendable {
        var requiresUnar = false
        var encoding: String?
    }

    static func inspect(_ data: Data) -> Inspection {
        guard data.count >= 22 else { return Inspection() }
        let start = max(0, data.count - 65_557)
        guard let end = stride(from: data.count - 22, through: start, by: -1).first(where: {
            integer(data, at: $0, count: 4) == 0x06054b50
                && $0 + 22 + Int(integer(data, at: $0 + 20, count: 2)) == data.count
        }) else { return Inspection() }
        var offset = integer(data, at: end + 16, count: 4)
        var size = integer(data, at: end + 12, count: 4)
        var count = integer(data, at: end + 10, count: 2)
        if offset == 0xffffffff || size == 0xffffffff || count == 0xffff {
            guard end >= 20, data.count >= 56, integer(data, at: end - 20, count: 4) == 0x07064b50 else { return Inspection() }
            let record = integer(data, at: end - 12, count: 8)
            guard record <= UInt64(data.count - 56),
                  integer(data, at: Int(record), count: 4) == 0x06064b50 else { return Inspection() }
            count = integer(data, at: Int(record) + 32, count: 8)
            size = integer(data, at: Int(record) + 40, count: 8)
            offset = integer(data, at: Int(record) + 48, count: 8)
        }
        guard offset <= UInt64(data.count), size <= 16_000_000,
              size <= UInt64(data.count) - offset else { return Inspection() }
        let limit = Int(offset + size)
        var cursor = Int(offset)
        var windowsNames = false
        var legacyBytes = Set<UInt8>()
        for _ in 0..<min(count, 100_001) {
            guard cursor <= limit - 46, integer(data, at: cursor, count: 4) == 0x02014b50 else { return Inspection() }
            let flags = integer(data, at: cursor + 8, count: 2)
            let length = Int(integer(data, at: cursor + 28, count: 2))
            let extra = Int(integer(data, at: cursor + 30, count: 2))
            let comment = Int(integer(data, at: cursor + 32, count: 2))
            let next = cursor + 46 + length + extra + comment
            guard next <= limit else { return Inspection() }
            let name = data[(cursor + 46)..<(cursor + 46 + length)]
            if flags & 0x800 == 0, String(bytes: name, encoding: .utf8) == nil {
                legacyBytes.formUnion(name.filter { $0 >= 0x80 })
                windowsNames = !legacyBytes.isEmpty
            }
            cursor = next
        }
        guard cursor == limit else { return Inspection() }
        let cp852: Set<UInt8> = [0xa5, 0x86, 0xa9, 0x88, 0xe4, 0xa2, 0x98, 0xab, 0xbe,
                               0xa4, 0x8f, 0xa8, 0x9d, 0xe3, 0xe0, 0x97, 0x8d, 0xbd]
        let cp1250: Set<UInt8> = [0xb9, 0xe6, 0xea, 0xb3, 0xf1, 0xf3, 0x9c, 0x9f, 0xbf,
                                0xa5, 0xc6, 0xca, 0xa3, 0xd1, 0xd3, 0x8c, 0x8f, 0xaf]
        var encoding: String?
        if legacyBytes.count >= 3 {
            if legacyBytes.isSubset(of: cp852), !legacyBytes.isSubset(of: cp1250) { encoding = "IBM852" }
            if legacyBytes.isSubset(of: cp1250), !legacyBytes.isSubset(of: cp852) { encoding = "windows-1250" }
        }
        return Inspection(requiresUnar: windowsNames, encoding: encoding)
    }

    private static func integer(_ data: Data, at offset: Int, count: Int) -> UInt64 {
        (0..<count).reduce(UInt64(0)) { $0 | UInt64(data[offset + $1]) << ($1 * 8) }
    }
}
