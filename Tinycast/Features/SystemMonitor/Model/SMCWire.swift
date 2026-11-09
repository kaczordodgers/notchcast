import Foundation

nonisolated enum SMCWire {
    static let size = 80

    enum Command: UInt8, Sendable {
        case read = 5
        case write = 6
        case keyAtIndex = 8
        case keyInfo = 9
    }

    static func code(_ key: String) -> UInt32? {
        let bytes = Array(key.utf8)
        guard bytes.count == 4, bytes.allSatisfy({ $0 < 128 }) else { return nil }
        return bytes.reduce(0) { $0 << 8 | UInt32($1) }
    }

    static func request(_ command: Command, key: UInt32 = 0, size: Int = 0,
                        index: UInt32 = 0, payload: [UInt8] = []) -> [UInt8]? {
        guard (0...32).contains(size), payload.count <= 32 else { return nil }
        var bytes = [UInt8](repeating: 0, count: Self.size)
        put(key, at: 0, in: &bytes)
        put(UInt32(size), at: 28, in: &bytes)
        bytes[42] = command.rawValue
        put(index, at: 44, in: &bytes)
        bytes.replaceSubrange(48..<(48 + payload.count), with: payload)
        return bytes
    }

    static func succeeded(_ reply: [UInt8]) -> Bool {
        reply.count == size && reply[40] == 0
    }

    static func data(_ reply: [UInt8], size: Int) -> [UInt8] { Array(reply[48..<(48 + size)]) }

    static func keyInfo(_ reply: [UInt8]) -> SMCValue.KeyInfo? {
        guard succeeded(reply) else { return nil }
        let size = Int(integer(reply, at: 28))
        guard (1...32).contains(size), let type = string(integer(reply, at: 32)) else { return nil }
        return SMCValue.KeyInfo(size: size, type: type, attributes: reply[36])
    }

    static func key(_ reply: [UInt8]) -> String? {
        guard succeeded(reply) else { return nil }
        let code = integer(reply, at: 0)
        return code == 0 ? nil : string(code)
    }

    private static func string(_ code: UInt32) -> String? {
        String(bytes: (0..<4).map { UInt8(truncatingIfNeeded: code >> (24 - 8 * $0)) }, encoding: .ascii)
    }

    private static func put(_ value: UInt32, at offset: Int, in bytes: inout [UInt8]) {
        for index in 0..<4 { bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index)) }
    }

    private static func integer(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }
}
