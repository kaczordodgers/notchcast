import Foundation

struct TreadmillStream: Sendable {
    private var buffer: [UInt8] = []
    private static let maximumLength = 24

    mutating func feed(_ data: Data) -> [TreadmillProtocol.Message] {
        var messages: [TreadmillProtocol.Message] = []
        for byte in data {
            buffer.append(byte)
            while !buffer.isEmpty {
                guard let start = buffer.firstIndex(of: 0x02) else {
                    buffer.removeAll(keepingCapacity: true)
                    break
                }
                if start > 0 { buffer.removeFirst(start) }
                if let (length, message) = Self.parse(buffer) {
                    buffer.removeFirst(length)
                    messages.append(message)
                } else if let later = buffer.indices.dropFirst().first(where: {
                    buffer[$0] == 0x02 && Self.parse(Array(buffer[$0...])) != nil
                }) {
                    buffer.removeFirst(later)
                } else if buffer.count >= Self.maximumLength {
                    buffer.removeFirst()
                } else {
                    break
                }
            }
        }
        return messages
    }

    private static func parse(_ bytes: [UInt8]) -> (Int, TreadmillProtocol.Message)? {
        guard bytes.count >= 5 else { return nil }
        if bytes[1] == 0x51 {
            for length in [6, 19] where bytes.count >= length && fits(bytes, length) {
                if let status = TreadmillStatus(body: Array(bytes[2..<(length - 2)])) {
                    return (length, .status(status))
                }
            }
            return nil
        }
        guard [0x40, 0x50, 0x53].contains(bytes[1]) else { return nil }
        for length in 5...min(bytes.count, maximumLength) where fits(bytes, length) {
            return (length, .reply(head: bytes[1], command: bytes[2], payload: Array(bytes[3..<(length - 2)])))
        }
        return nil
    }

    private static func fits(_ bytes: [UInt8], _ length: Int) -> Bool {
        bytes[length - 1] == 0x03
            && bytes[length - 2] == TreadmillProtocol.checksum(bytes[1..<(length - 2)])
    }
}
