// notchcast-sources: Tinycast/Features/CommandRunner/Service/CommandProcessRunner.swift
// notchcast-sources: Tinycast/Features/CommandRunner/Service/CatalogShellCommandRunner.swift
// notchcast-sources: Tinycast/Features/CommandRunner/Model/HostCommandCatalog.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Downloads/Model/DownloadTool.swift Tinycast/Platform/ExecutableLocator.swift
// notchcast-kit: platform
import Darwin
import Foundation

@main struct CommandProcessTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appending(path: "fake.sh")
        let pidFile = root.appending(path: "grandchild")
        try "sleep 120 &\necho $! > \"$1\"\nwait\n".write(to: script, atomically: true, encoding: .utf8)
        let task = Task {
            try await CommandProcessRunner.run(.init(executable: "/bin/sh", arguments: [script.path, pidFile.path],
                                                     workingDirectory: root.path))
        }
        let deadline = ContinuousClock.now + .seconds(10)
        while !FileManager.default.fileExists(atPath: pidFile.path) {
            precondition(ContinuousClock.now < deadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Cancellation expected") } catch is CancellationError {}
        for _ in 0..<100 where kill(pid, 0) == 0 { try await Task.sleep(for: .milliseconds(10)) }
        precondition(kill(pid, 0) != 0)
        print("Process group cancellation passed")
    }
}
