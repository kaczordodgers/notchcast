import Foundation
import IOKit
import Synchronization

nonisolated final class SMCClient: Sendable {
    private let connection: io_connect_t
    private let metadata = Mutex<[String: SMCValue.KeyInfo?]>([:])

    init?() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
        self.connection = connection
    }

    deinit { IOServiceClose(connection) }

    func keyInfo(_ key: String) -> SMCValue.KeyInfo? {
        metadata.withLock { cache in
            if let cached = cache[key] { return cached }
            guard let code = SMCWire.code(key) else { return nil }
            guard let reply = call(.keyInfo, key: code) else { return nil }
            let info = SMCWire.keyInfo(reply)
            if info != nil || reply[40] == 0x84 { cache[key] = .some(info) }
            return info
        }
    }

    func read(_ key: String) -> SMCValue? {
        guard let code = SMCWire.code(key), let info = keyInfo(key),
              let reply = call(.read, key: code, size: info.size),
              SMCWire.succeeded(reply) else { return nil }
        return SMCValue(info: info, bytes: SMCWire.data(reply, size: info.size))
    }

    func value(_ key: String) -> Double? { read(key)?.number }

    func keyCount() -> UInt32? {
        guard let count = value("#KEY"), count >= 0, count <= Double(UInt32.max) else { return nil }
        return UInt32(count)
    }

    func key(at index: UInt32) -> String? {
        guard let reply = call(.keyAtIndex, index: index) else { return nil }
        return SMCWire.key(reply)
    }

    func keys(startingAt index: UInt32 = 0, limit: Int = 128) -> [String] {
        guard limit > 0, let count = keyCount(), index < count else { return [] }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.045
        let end = UInt64(index) + min(UInt64(count - index), UInt64(limit))
        var result: [String] = []
        for offset in UInt64(index)..<end {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            if let key = key(at: UInt32(offset)) { result.append(key) }
        }
        return result
    }

    private func call(_ command: SMCWire.Command, key: UInt32 = 0, size: Int = 0,
                      index: UInt32 = 0) -> [UInt8]? {
        guard let request = SMCWire.request(command, key: key, size: size, index: index) else { return nil }
        var reply = [UInt8](repeating: 0, count: SMCWire.size)
        var replySize = reply.count
        let status = request.withUnsafeBytes { input in
            reply.withUnsafeMutableBytes { output in
                IOConnectCallStructMethod(connection, 2, input.baseAddress, input.count,
                                          output.baseAddress, &replySize)
            }
        }
        guard status == KERN_SUCCESS, replySize == SMCWire.size else { return nil }
        return reply
    }
}
