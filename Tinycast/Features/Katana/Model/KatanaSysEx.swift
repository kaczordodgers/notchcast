enum KatanaSysEx {
    static let header: [UInt8] = [0xF0, 0x41, 0x10, 0x01, 0x05, 0x07]
    static let activeChannel = 0
    static let selectChannel = 0x7F000100
    static let patchWrite = 0x7F000104
    static let previewMute = 0x7F010109
    static let export = 0x7F01010A
    static let usbSettings = 0x10000200

    struct Message: Equatable {
        let command: UInt8
        let address: Int
        let data: [UInt8]
    }

    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        UInt8((128 - bytes.reduce(0) { $0 + Int($1) } % 128) % 128)
    }

    static func bytes(_ address: Int) throws -> [UInt8] {
        guard (0...0x7F7F7F7F).contains(address) else { throw KatanaError.invalidData }
        let bytes = [24, 16, 8, 0].map { UInt8((address >> $0) & 0xFF) }
        guard bytes.allSatisfy({ $0 < 0x80 }) else { throw KatanaError.invalidData }
        return bytes
    }

    static func write(_ address: Int, _ data: [UInt8]) throws -> [UInt8] {
        guard !data.isEmpty, data.count <= 128, data.allSatisfy({ $0 < 0x80 }) else {
            throw KatanaError.invalidData
        }
        let body = try bytes(address) + data
        return header + [0x12] + body + [checksum(body), 0xF7]
    }

    static func read(_ address: Int, count: Int) throws -> [UInt8] {
        guard (1...128).contains(count) else { throw KatanaError.invalidData }
        let body = try bytes(address) + [0, 0, UInt8(count >> 7), UInt8(count & 0x7F)]
        return header + [0x11] + body + [checksum(body), 0xF7]
    }

    static func decode(_ packet: [UInt8]) throws -> Message {
        guard packet.count >= 14, Array(packet.prefix(6)) == header, packet.last == 0xF7,
              packet[6] == 0x11 || packet[6] == 0x12 else { throw KatanaError.invalidData }
        let body = Array(packet[7..<(packet.count - 2)])
        guard body.allSatisfy({ $0 < 0x80 }), checksum(body) == packet[packet.count - 2] else {
            throw KatanaError.invalidData
        }
        let address = body.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        return Message(command: packet[6], address: address, data: Array(body.dropFirst(4)))
    }

    static func patchAddress(region: UInt8, offset: Int = 0, page: Int = 0) -> Int {
        0x20000000 | (page << 16) | ((Int(region) + (offset >> 7)) << 8) | (offset & 0x7F)
    }

    static func name(_ bytes: [UInt8]) -> String {
        String(bytes: bytes.map { (0x20...0x7E).contains($0) ? $0 : 0x20 }, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
