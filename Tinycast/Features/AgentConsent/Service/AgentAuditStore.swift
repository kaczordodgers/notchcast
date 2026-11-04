import Foundation
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
        try Task.checkCancellation()
        try lock.withLock { _ in
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            let current = directory.appendingPathComponent("audit.jsonl")
            let archive = directory.appendingPathComponent("audit.previous.jsonl")
            var data = try JSONEncoder().encode(entry)
            data.append(0x0A)
            guard data.count <= maximumBytes else { throw CocoaError(.fileWriteOutOfSpace) }
            if manager.fileExists(atPath: current.path) {
                let attributes = try manager.attributesOfItem(atPath: current.path)
                let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
                if size + data.count > maximumBytes {
                    if manager.fileExists(atPath: archive.path) { try manager.removeItem(at: archive) }
                    try manager.moveItem(at: current, to: archive)
                }
            }
            if !manager.fileExists(atPath: current.path) {
                guard manager.createFile(atPath: current.path, contents: nil,
                                         attributes: [.posixPermissions: 0o600]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.path)
            let handle = try FileHandle(forWritingTo: current)
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }
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
                    result.append(try JSONDecoder().decode(AgentAuditEntry.self, from: Data(line)))
                }
            }
            return result
        }
    }
}
