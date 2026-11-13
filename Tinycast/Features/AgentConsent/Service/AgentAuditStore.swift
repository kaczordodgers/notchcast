import Foundation
import Darwin
import Synchronization
import OSLog

final class AgentAuditStore: Sendable {
    private let directory: URL
    private let maximumBytes: Int
    private let lock = Mutex(false)

    init(directory: URL, maximumBytes: Int = 1_048_576) {
        self.directory = directory
        self.maximumBytes = max(1024, maximumBytes)
    }

    @concurrent
    func append(_ entry: AgentAuditEntry) async throws {
        try lock.withLock { rotationFailureLogged in
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            let directoryDescriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directoryDescriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            defer { close(directoryDescriptor) }
            var data = try JSONEncoder().encode(entry)
            data.append(0x0A)
            guard data.count <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
            var (descriptor, status) = try openLog(directoryDescriptor, name: "audit.jsonl", flags: O_WRONLY | O_CREAT)
            defer { if descriptor >= 0 { close(descriptor) } }
            if status.st_size + Int64(data.count) > Int64(maximumBytes) {
                if renameat(directoryDescriptor, "audit.jsonl", directoryDescriptor, "audit.previous.jsonl") == 0 {
                    close(descriptor)
                    descriptor = -1
                    (descriptor, status) = try openLog(directoryDescriptor, name: "audit.jsonl",
                        flags: O_WRONLY | O_CREAT | O_EXCL)
                } else if !rotationFailureLogged {
                    rotationFailureLogged = true
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "Notchcast", category: "AgentAudit")
                        .error("Audit rotation failed; continuing in the current log. errno=\(errno)")
                }
            }
            guard fchmod(descriptor, 0o600) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        }
    }

    @concurrent
    func entries() async throws -> [AgentAuditEntry] {
        try Task.checkCancellation()
        return try lock.withLock { _ in
            let directoryDescriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if directoryDescriptor < 0, errno == ENOENT { return [] }
            guard directoryDescriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            defer { close(directoryDescriptor) }
            var result: [AgentAuditEntry] = []
            for name in ["audit.previous.jsonl", "audit.jsonl"] {
                let descriptor: Int32
                do {
                    (descriptor, _) = try openLog(directoryDescriptor, name: name, flags: O_RDONLY)
                } catch let error as POSIXError where error.code == .ENOENT {
                    continue
                }
                defer { close(descriptor) }
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
                let data = try handle.read(upToCount: maximumBytes) ?? Data()
                for line in data.split(separator: 0x0A) {
                    if let entry = try? JSONDecoder().decode(AgentAuditEntry.self, from: Data(line)) { result.append(entry) }
                }
            }
            return result
        }
    }

    private func openLog(_ directoryDescriptor: Int32, name: String, flags: Int32) throws -> (Int32, stat) {
        let descriptor = openat(directoryDescriptor, name, flags | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        do {
            var status = stat()
            guard fstat(descriptor, &status) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            guard status.st_mode & S_IFMT == S_IFREG, status.st_nlink == 1 else {
                throw POSIXError(.EINVAL)
            }
            return (descriptor, status)
        } catch {
            close(descriptor)
            throw error
        }
    }
}
