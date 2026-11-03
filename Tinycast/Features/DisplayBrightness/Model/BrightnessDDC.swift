import Foundation

enum BrightnessDDC {
    static let chip: UInt32 = 0x37
    static let host: UInt32 = 0x51
    static let replyLength = 11

    static func request() -> [UInt8] { seal([0x82, 0x01, 0x10]) }

    static func write(_ value: UInt16) -> [UInt8] {
        seal([0x84, 0x03, 0x10, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    static func parse(_ reply: [UInt8]) -> (current: UInt16, maximum: UInt16)? {
        guard reply.count == replyLength, reply[0] == 0x6E, reply[1] == 0x88,
              reply[2] == 0x02, reply[3] == 0, reply[4] == 0x10,
              reply.reduce(UInt8(0x50), ^) == 0 else { return nil }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maximum > 0, current <= maximum else { return nil }
        return (current, maximum)
    }

    static func deviceValue(_ level: Double, maximum: UInt16) -> UInt16 {
        UInt16((BrightnessLevel(level).hardware * Double(maximum)).rounded())
    }

    private static func seal(_ body: [UInt8]) -> [UInt8] {
        body + [body.reduce(UInt8(0x6E ^ 0x51), ^)]
    }
}
