// notchcast-sources: Tinycast/Features/Archives/Model/*.swift Tinycast/Features/Archives/Service/*.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Darwin
import Foundation
import Synchronization

@main
struct ArchiveChildCancelTest {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }

    static func main() async throws {
        try await check(escaped: false)
        try await check(escaped: true)
    }

    static func check(escaped: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appending(path: "extractor")
        let pidFile = root.appending(path: "child.pid")
        try """
        #!/usr/bin/python3
        import os, signal, sys, time
        if len(sys.argv) > 1: sys.exit(int(sys.argv[1]))
        child = os.fork()
        if child == 0:
            if \(escaped ? "True" : "False"): os.setsid()
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            time.sleep(30)
            os._exit(0)
        with open('\(pidFile.path).tmp', 'w') as file: file.write(str(child))
        os.rename('\(pidFile.path).tmp', '\(pidFile.path)')
        os._exit(0)
        """.write(to: script, atomically: false, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        for status: Int32 in [0, 5] {
            let result = try await ArchiveProcess.run(tool: script, arguments: [String(status)])
            require(result.status == status, "Extractor exit status changed: \(result.status), expected \(status)")
        }
        let completed = Mutex(false)
        let task = Task {
            defer { completed.withLock { $0 = true } }
            return try await ArchiveProcess.run(tool: script, arguments: [], progress: {
                await Task.yield()
            })
        }
        // A cold python3 on a loaded CI runner can take seconds to start.
        for _ in 0..<1000 {
            if FileManager.default.fileExists(atPath: pidFile.path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let child = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            require(false, "Extractor never reported its child pid, escaped=\(escaped)")
            return
        }
        defer { kill(child, SIGKILL) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        try await Task.sleep(for: .seconds(5))
        let finished = completed.withLock { $0 }
        let childStopped = kill(child, 0) == -1 && errno == ESRCH
        kill(child, SIGKILL)
        let result = await task.result
        require(finished, "Cancellation hung after extractor parent exited, escaped=\(escaped)")
        require(escaped || childStopped, "Cancellation left the extractor child running, pid=\(child)")
        guard case .failure(let error) = result, error is CancellationError else {
            require(false, "Cancelled extractor reported success: \(result)")
            return
        }
        print("PASS: child pipe cancellation, escaped=\(escaped)")
    }
}
