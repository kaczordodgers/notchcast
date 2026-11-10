import Foundation
import IOKit

enum FanSMC {
    enum Failure: Error { case invalidValue, unavailable, refused }

    struct Info {
        let size: Int
        let type: String
    }

    protocol Access {
        func info(_ key: String) throws -> Info?
        func read(_ key: String, info: Info) throws -> [UInt8]
        func write(_ key: String, bytes: [UInt8]) throws
    }

    static func target(minimum: Double, maximum: Double, command: RootContract.Command) throws -> Double {
        guard minimum.isFinite, maximum.isFinite, minimum >= 0,
              maximum > minimum, maximum <= 20_000 else { throw Failure.invalidValue }
        switch command {
        case .fansMedium: return minimum + 0.6 * (maximum - minimum)
        case .fansMax: return maximum
        default: throw Failure.invalidValue
        }
    }

    static func decode(_ bytes: [UInt8], info: Info) throws -> Double {
        // The helper reads only the types its encoder can write back.
        _ = try encode(0, info: info)
        let decoded = SMCValue( // drift: keep the helper decodes with the app's one SMC decoder
            info: .init(size: info.size, type: info.type, attributes: 0), bytes: bytes)
        guard let value = decoded.number, value >= 0 else { throw Failure.invalidValue }
        return value
    }

    static func encode(_ value: Double, info: Info) throws -> [UInt8] {
        guard value.isFinite, value >= 0 else { throw Failure.invalidValue }
        if info.type == "flt ", info.size == 4 {
            let number = Float(value)
            guard number.isFinite else { throw Failure.invalidValue }
            return (0..<4).map { UInt8(truncatingIfNeeded: number.bitPattern >> (8 * $0)) }
        }
        let integer: Double
        switch (info.type, info.size) {
        case ("fpe2", 2): integer = (value * 4).rounded()
        case ("ui8 ", 1), ("ui16", 2), ("ui32", 4):
            guard value == value.rounded() else { throw Failure.invalidValue }
            integer = value
        default: throw Failure.invalidValue
        }
        guard integer < pow(2, Double(8 * info.size)) else { throw Failure.invalidValue }
        let raw = UInt32(integer)
        return (0..<info.size).map { UInt8(truncatingIfNeeded: raw >> (8 * (info.size - 1 - $0))) }
    }

    struct Controller {
        let smc: any Access
        var now: () -> ContinuousClock.Instant = { .now }
        var pause: (Duration) -> Void = {
            Thread.sleep(forTimeInterval: Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18)
        }

        func run(_ command: RootContract.Command) throws {
            if command == .fansAuto { return try restoreAuto() }
            guard command == .fansMedium || command == .fansMax else { throw Failure.invalidValue }
            do {
                try setManual(command)
            } catch {
                try? restoreAuto()
                throw error
            }
        }

        private func count() throws -> Int {
            let value = try value("FNum")
            guard value == value.rounded(), value <= 9 else { throw Failure.invalidValue }
            return Int(value)
        }

        private func modeKey(_ fan: Int) throws -> String {
            for key in ["F\(fan)Md", "F\(fan)md"] where try smc.info(key) != nil { return key }
            throw Failure.unavailable
        }

        private func setManual(_ command: RootContract.Command) throws {
            let count = try count()
            guard count > 0 else { throw Failure.unavailable }
            let fans = try (0..<count).map { fan -> (mode: String, target: String, bytes: [UInt8]) in
                let target = try FanSMC.target(
                    minimum: value("F\(fan)Mn"), maximum: value("F\(fan)Mx"), command: command
                )
                guard try value("F\(fan)Ac") <= 20_000,
                      try value("F\(fan)Tg") <= 20_000 else { throw Failure.invalidValue }
                let mode = try modeKey(fan)
                guard try value(mode) <= 3 else { throw Failure.invalidValue }
                _ = try encode(1, info: known(mode))
                let key = "F\(fan)Tg"
                return (mode, key, try encode(target, info: known(key)))
            }
            let deadline = now().advanced(by: .seconds(5))
            if try smc.info("Ftst") != nil, try value("Ftst") != 1 { try write(1, to: "Ftst") }
            for fan in fans {
                while true {
                    guard now() < deadline else { throw Failure.refused }
                    try write(1, to: fan.mode)
                    if try value(fan.mode) == 1 { break }
                    let remaining = now().duration(to: deadline)
                    guard remaining > .zero else { throw Failure.refused }
                    pause(min(.milliseconds(100), remaining))
                }
                try smc.write(fan.target, bytes: fan.bytes)
            }
        }

        private func restoreAuto() throws {
            var results: [Result<Void, any Error>] = []
            let releaseFans = Result {
                for fan in 0..<(try count()) {
                    results.append(Result { try write(0, to: modeKey(fan)) })
                }
            }
            results.append(releaseFans)
            results.append(Result { if try smc.info("Ftst") != nil { try write(0, to: "Ftst") } })
            for result in results { try result.get() }
        }

        private func known(_ key: String) throws -> Info {
            guard let info = try smc.info(key) else { throw Failure.unavailable }
            return info
        }

        private func value(_ key: String) throws -> Double {
            let info = try known(key)
            return try decode(smc.read(key, info: info), info: info)
        }

        private func write(_ value: Double, to key: String) throws {
            try smc.write(key, bytes: encode(value, info: known(key)))
        }
    }

    final class Connection: Access {
        private let connection: io_connect_t

        init() throws {
            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
            guard service != 0 else { throw Failure.unavailable }
            defer { IOObjectRelease(service) }
            var connection: io_connect_t = 0
            guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
                throw Failure.unavailable
            }
            self.connection = connection
        }

        deinit { IOServiceClose(connection) }

        func info(_ key: String) throws -> Info? {
            let reply = try call(9, key: key)
            if reply[40] == 0x84 { return nil }
            try check(reply)
            let size = Int(Self.integer(reply, at: 28))
            guard (1...32).contains(size) else { throw Failure.invalidValue }
            let code = Self.integer(reply, at: 32)
            let type = String(decoding: (0..<4).map {
                UInt8(truncatingIfNeeded: code >> (24 - 8 * $0))
            }, as: UTF8.self)
            return Info(size: size, type: type)
        }

        func read(_ key: String, info: Info) throws -> [UInt8] {
            let reply = try call(5, key: key, size: info.size)
            try check(reply)
            return Array(reply[48..<48 + info.size])
        }

        func write(_ key: String, bytes: [UInt8]) throws {
            try check(call(6, key: key, size: bytes.count, payload: bytes))
        }

        private func call(_ command: UInt8, key: String, size: Int = 0, payload: [UInt8] = []) throws -> [UInt8] {
            guard key.utf8.count == 4, (0...32).contains(size), payload.count <= 32 else {
                throw Failure.invalidValue
            }
            var request = [UInt8](repeating: 0, count: 80)
            let code = key.utf8.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            for offset in 0..<4 {
                request[offset] = UInt8(truncatingIfNeeded: code >> (8 * offset))
                request[28 + offset] = UInt8(truncatingIfNeeded: UInt32(size) >> (8 * offset))
            }
            request[42] = command
            request.replaceSubrange(48..<48 + payload.count, with: payload)
            var reply = [UInt8](repeating: 0, count: 80)
            var replySize = reply.count
            let status = IOConnectCallStructMethod(connection, 2, request, request.count, &reply, &replySize)
            guard status == KERN_SUCCESS, replySize == reply.count else { throw Failure.refused }
            return reply
        }

        private func check(_ reply: [UInt8]) throws {
            guard reply[40] == 0 else { throw Failure.refused }
        }

        private static func integer(_ bytes: [UInt8], at offset: Int) -> UInt32 {
            (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
        }
    }
}
