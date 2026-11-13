import Foundation

@main
struct AuditSymlinkTests {
    static func main() async throws {
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
        print("PASS: existing and dangling audit symlinks rejected; target data and mode unchanged")
    }
}
