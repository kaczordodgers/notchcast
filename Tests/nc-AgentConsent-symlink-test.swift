import Foundation
import Darwin

@main
struct AuditSymlinkTests {
    static func main() async throws {
        alarm(20)
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        let target = root.appendingPathComponent("target")
        let original = Data("untouched".utf8)
        try original.write(to: target)
        try manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        let entry = AgentAuditEntry(time: Date(), agentID: "a", client: "test", surface: .cli,
            actionID: "write", parameters: [:], verdict: .ran, succeeded: true, duration: 0.5)
        for dangling in [false, true] {
            let directory = root.appendingPathComponent(dangling ? "dangling" : "existing")
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = dangling ? root.appendingPathComponent("absent") : target
            try manager.createSymbolicLink(at: directory.appendingPathComponent("audit.jsonl"),
                withDestinationURL: destination)
            do {
                try await AgentAuditStore(directory: directory).append(entry)
                preconditionFailure("Audit append must reject a symlink")
            } catch {}
            let contents = try Data(contentsOf: target)
            precondition(contents == original)
            let attributes = try manager.attributesOfItem(atPath: target.path)
            precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o644)
            precondition(!manager.fileExists(atPath: root.appendingPathComponent("absent").path))
        }
        let hardLinkDirectory = root.appendingPathComponent("hard-link")
        try manager.createDirectory(at: hardLinkDirectory, withIntermediateDirectories: true)
        try manager.linkItem(at: target, to: hardLinkDirectory.appendingPathComponent("audit.jsonl"))
        do {
            try await AgentAuditStore(directory: hardLinkDirectory).append(entry)
            preconditionFailure("Audit append must reject a hard link")
        } catch {}
        let hardLinkContents = try Data(contentsOf: target)
        precondition(hardLinkContents == original)
        let attributes = try manager.attributesOfItem(atPath: target.path)
        precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o644)
        print("PASS: hard link rejected; target data and mode unchanged")
        for name in ["audit.jsonl", "audit.previous.jsonl"] {
            let directory = root.appendingPathComponent("fifo-\(name)")
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            precondition(mkfifo(directory.appendingPathComponent(name).path, 0o600) == 0)
            let store = AgentAuditStore(directory: directory)
            if name == "audit.jsonl" {
                do {
                    try await store.append(entry)
                    preconditionFailure("Audit append must reject a FIFO")
                } catch {}
            }
            do {
                _ = try await store.entries()
                preconditionFailure("Audit read must reject a FIFO")
            } catch {}
            print("PASS: FIFO rejected without blocking at \(name)")
        }
        for name in ["audit.jsonl", "audit.previous.jsonl"] {
            let directory = root.appendingPathComponent("read-link-\(name)")
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.createSymbolicLink(atPath: directory.appendingPathComponent(name).path,
                withDestinationPath: "/dev/zero")
            do {
                _ = try await AgentAuditStore(directory: directory).entries()
                preconditionFailure("Audit read must reject a symlink")
            } catch {}
        }
        let blockedRotation = root.appendingPathComponent("rotation")
        let previous = blockedRotation.appendingPathComponent("audit.previous.jsonl")
        try manager.createDirectory(at: previous, withIntermediateDirectories: true)
        let store = AgentAuditStore(directory: blockedRotation, maximumBytes: 1024)
        for _ in 0..<20 { try await store.append(entry) }
        var status = stat()
        precondition(lstat(previous.path, &status) == 0 && status.st_mode & S_IFMT == S_IFDIR)
        let contents = try Data(contentsOf: blockedRotation.appendingPathComponent("audit.jsonl"))
        precondition(contents.count > 1024 && contents.split(separator: 0x0A).count == 20)
        print("PASS: blocked rotation keeps all appends and leaves planted directory intact")
        let capped = root.appendingPathComponent("capped")
        try manager.createDirectory(at: capped, withIntermediateDirectories: true)
        var oversized = Data(repeating: 0x20, count: 1024)
        oversized.append(0x0A)
        oversized.append(try JSONEncoder().encode(entry))
        try oversized.write(to: capped.appendingPathComponent("audit.jsonl"))
        let boundedEntries = try await AgentAuditStore(directory: capped, maximumBytes: 1024).entries()
        precondition(boundedEntries.isEmpty)
        print("PASS: reads stop at the rotation cap; both read symlinks rejected")
    }
}
