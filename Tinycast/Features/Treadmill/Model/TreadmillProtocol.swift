import Foundation

enum TreadmillProtocol {
    enum Message: Equatable, Sendable {
        case status(TreadmillStatus)
        case reply(head: UInt8, command: UInt8, payload: [UInt8])
    }

    static let speedRange = 1.0...6.0
    static let maximumMinutes = 1092
    static let queryStatus = frame([0x51])
    static let pause = frame([0x53, 0x0A])
    static let resume = frame([0x53, 0x09])
    static let stop = frame([0x53, 0x03])

    static func start(minutes: Int) throws -> Data {
        guard (0...maximumMinutes).contains(minutes) else { throw TreadmillFailure.invalidMinutes }
        let seconds = minutes * 60
        return frame([0x53, 0x01, 0, 0, UInt8(seconds & 0xFF), UInt8(seconds >> 8), 0, 0, 0, 0])
    }

    static func speed(_ kmh: Double) throws -> Data {
        guard kmh.isFinite, speedRange.contains(kmh) else { throw TreadmillFailure.invalidSpeed }
        return frame([0x53, 0x02, UInt8((kmh * 10).rounded()), 0])
    }

    static func frame(_ body: [UInt8]) -> Data { Data([0x02] + body + [checksum(body), 0x03]) }

    static func checksum(_ body: some Sequence<UInt8>) -> UInt8 {
        body.reduce(UInt8(0)) { $0 &+ $1 } ^ 0x5A
    }
}
