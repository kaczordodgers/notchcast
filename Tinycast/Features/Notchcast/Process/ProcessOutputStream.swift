import Darwin
import Foundation
import Synchronization

nonisolated final class ProcessOutputStream: Sendable {
    let pipe = Pipe()
    private let limit: Int?
    private let onLine: (@Sendable (String) -> Void)?
    private let onData: (@Sendable (Data) async throws -> Void)?
    private let failure = Mutex<(any Error)?>(nil)
    private let captured = Mutex(Data())
    private let readers = DispatchGroup()

    init(limit: Int?, onLine: (@Sendable (String) -> Void)? = nil,
         onData: (@Sendable (Data) async throws -> Void)? = nil) {
        self.limit = limit
        self.onLine = onLine
        self.onData = onData
    }
    var data: Data { captured.withLock { $0 } }
    var error: (any Error)? { failure.withLock { $0 } }
    func start(deadline: @escaping @Sendable () -> ContinuousClock.Instant?, failed: @escaping @Sendable () -> Void) {
        readers.enter()
        Thread.detachNewThread { @Sendable in
            defer { self.readers.leave(); try? self.pipe.fileHandleForReading.close() }
            let descriptor = self.pipe.fileHandleForReading.fileDescriptor
            var pending = Data()
            var buffer = [UInt8](repeating: 0, count: 8192)
            while deadline().map({ ContinuousClock.now < $0 }) ?? true {
                var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                let ready = poll(&event, 1, 50)
                if ready < 0 && errno == EINTR { continue }
                if ready == 0 { continue }
                guard ready > 0 else { break }
                let count = Darwin.read(descriptor, &buffer, buffer.count)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { break }
                if let onData = self.onData {
                    let chunk = Data(buffer.prefix(count))
                    let consumed = DispatchSemaphore(value: 0)
                    Task.detached {
                        defer { consumed.signal() }
                        do { try await onData(chunk) } catch {
                            self.failure.withLock { $0 = error }
                            failed()
                        }
                    }
                    consumed.wait()
                    if self.error != nil { break }
                }
                self.captured.withLock {
                    if self.onData == nil || self.limit != nil { $0.append(contentsOf: buffer.prefix(count)) }
                    if let limit = self.limit { Self.trim(&$0, limit: limit) }
                }
                if let onLine = self.onLine {
                    pending.append(contentsOf: buffer.prefix(count))
                    while let newline = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                        let line = String(bytes: pending[..<newline], encoding: .utf8) ?? ""
                        pending.removeSubrange(...newline)
                        if !line.isEmpty { onLine(line) }
                    }
                    Self.trim(&pending, limit: 65_536)
                }
            }
            if let onLine = self.onLine, !pending.isEmpty {
                onLine(String(bytes: pending, encoding: .utf8) ?? "")
            }
        }
    }
    func wait() { readers.wait() }
    private static func trim(_ data: inout Data, limit: Int) {
        if data.count > limit { data.removeFirst(data.count - limit) }
        while let first = data.first, first & 0xC0 == 0x80 { data.removeFirst() }
    }
}
