import Foundation
import Darwin
import Synchronization

final class AgentAuditStore: Sendable {
    private let directory: URL
    private let maximumBytes: Int
    private let lock = Mutex(())

    init(directory: URL, maximumBytes: Int = 1_048_576) {
        self.directory = directory
        self.maximumBytes = max(1024, maximumBytes)
    }

    @concurrent
    func append(_ entry: AgentAuditEntry) async throws {
        try lock.withLock { _ in
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            let directoryDescriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard directoryDescriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            defer { close(directoryDescriptor) }
            var data = try JSONEncoder().encode(entry)
            data.append(0x0A)
            guard data.count <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
            var descriptor = openat(directoryDescriptor, "audit.jsonl", O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            defer { if descriptor >= 0 { close(descriptor) } }
            var status = stat()
            guard fstat(descriptor, &status) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            guard status.st_mode & S_IFMT == S_IFREG else { throw CocoaError(.fileWriteUnknown) }
            if status.st_size + Int64(data.count) > Int64(maximumBytes) {
                guard renameat(directoryDescriptor, "audit.jsonl", directoryDescriptor, "audit.previous.jsonl") == 0 else {
                    throw POSIXError(.init(rawValue: errno) ?? .EIO)
                }
                close(descriptor)
                descriptor = openat(directoryDescriptor, "audit.jsonl",
                    O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
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
            var result: [AgentAuditEntry] = []
            for name in ["audit.previous.jsonl", "audit.jsonl"] {
                let url = directory.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let data = try Data(contentsOf: url)
                for line in data.split(separator: 0x0A) {
                    if let entry = try? JSONDecoder().decode(AgentAuditEntry.self, from: Data(line)) { result.append(entry) }
                }
            }
            return result
        }
    }
}
