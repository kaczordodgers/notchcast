import Darwin
import Foundation

enum AgentSocketIO {
    static let frameLimit = 1_048_576
    static let pathLimit = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    static func address(_ path: String) throws -> sockaddr_un {
        guard !path.utf8.contains(0), path.utf8.count <= pathLimit else { throw AgentReply.Code.failed }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { bytes in
            bytes.copyBytes(from: path.utf8)
        }
        return address
    }

    static func configure(_ descriptor: Int32) throws {
        var enabled: Int32 = 1
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
            fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0,
            setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size)) == 0
        else { throw AgentReply.Code.failed }
    }

    static func isSameUser(_ descriptor: Int32) -> Bool {
        var user: uid_t = 0
        var group: gid_t = 0
        return getpeereid(descriptor, &user, &group) == 0 && user == geteuid()
    }

    static func frame(_ value: some Encodable) throws -> Data {
        var data = try JSONEncoder().encode(value)
        guard data.count <= frameLimit else { throw AgentReply.Code.failed }
        data.append(UInt8(ascii: "\n"))
        return data
    }

    static func readLine(_ descriptor: Int32, timeout: Duration) throws -> Data {
        let deadline = ContinuousClock.now + timeout
        var data = Data()
        var bytes = [UInt8](repeating: 0, count: 4096)
        while data.count <= frameLimit {
            try wait(descriptor, events: POLLIN, deadline: deadline)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
            guard count > 0 else { throw AgentReply.Code.failed }
            if let end = bytes[..<count].firstIndex(of: UInt8(ascii: "\n")) {
                data.append(contentsOf: bytes[..<end])
                guard data.count <= frameLimit, end == count - 1 else { throw AgentReply.Code.badRequest }
                return data
            }
            data.append(contentsOf: bytes[..<count])
        }
        throw AgentReply.Code.badRequest
    }

    static func write(_ data: Data, to descriptor: Int32, timeout: Duration) throws {
        let deadline = ContinuousClock.now + timeout
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try wait(descriptor, events: POLLOUT, deadline: deadline)
                let count = Darwin.write(descriptor, bytes.baseAddress! + offset, bytes.count - offset)
                if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                guard count > 0 else { throw AgentReply.Code.failed }
                offset += count
            }
        }
    }

    private static func wait(_ descriptor: Int32, events: Int32, deadline: ContinuousClock.Instant) throws {
        while ContinuousClock.now < deadline {
            let remaining = ContinuousClock.now.duration(to: deadline).components
            let milliseconds = remaining.seconds * 1000 + remaining.attoseconds / 1_000_000_000_000_000
            var item = pollfd(fd: descriptor, events: Int16(events), revents: 0)
            let result = poll(&item, 1, Int32(clamping: max(1, milliseconds)))
            if result < 0 && errno == EINTR { continue }
            guard result > 0, item.revents & Int16(events) != 0 else { throw AgentReply.Code.failed }
            return
        }
        throw AgentReply.Code.failed
    }
}
