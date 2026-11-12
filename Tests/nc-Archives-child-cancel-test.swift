// notchcast-sources: Tinycast/Features/Archives/Model/*.swift Tinycast/Features/Archives/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Jobs/JobOutput.swift
// notchcast-kit: platform
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
        try await streamingChecks()
        let progress = Mutex((calls: 0, active: false))
        _ = try await ArchiveProcess.run(tool: URL(fileURLWithPath: "/bin/sleep"), arguments: ["0.6"], progress: {
            progress.withLock {
                require(!$0.active, "Idle progress callbacks overlap")
                $0.active = true
                $0.calls += 1
            }
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { continuation.resume() }
            }
            progress.withLock { $0.active = false }
        })
        require(progress.withLock { $0.calls == 1 && !$0.active }, "Idle progress was not awaited")
        try await Task.sleep(for: .milliseconds(300))
        require(progress.withLock { $0.calls == 1 && !$0.active }, "Progress outlived the operation")
        print("PASS: one idle progress callback, awaited teardown, no callback after return")
        try await check(escaped: false)
        try await check(escaped: true)
    }

    static func streamingChecks() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let perl = URL(fileURLWithPath: "/usr/bin/perl")
        let arguments = ["-e", "print pack('C*',0..255)x256"]
        let file = root.appending(path: "output")
        let bytes = Data((0..<65_536).map { UInt8($0 % 256) })
        let result = try await ArchiveProcess.run(tool: perl, arguments: arguments, captureOutput: true,
                                                 outputFile: file, maximumOutputBytes: Int64(bytes.count))
        require(result.output == bytes && result.outputBytes == bytes.count, "Binary capture or byte count changed")
        require(try Data(contentsOf: file) == bytes, "Binary output file changed")
        do {
            _ = try await ArchiveProcess.run(tool: perl, arguments: arguments, outputFile: file)
            require(false, "Existing output file was overwritten")
        } catch { require(try Data(contentsOf: file) == bytes, "Exclusive output creation changed the file") }
        let rejected = root.appending(path: "rejected")
        do {
            _ = try await ArchiveProcess.run(tool: perl, arguments: arguments, captureListing: true,
                captureOutput: true, outputFile: rejected, maximumOutputBytes: 0)
            require(false, "Expansion limit accepted output")
        } catch ArchiveFailure.expansionLimit {}
        require(try Data(contentsOf: rejected).isEmpty, "Rejected chunk reached the output file")
        do {
            _ = try await ArchiveProcess.run(tool: perl, arguments: ["-e", "print 'x'x16000001"], captureOutput: true)
            require(false, "Capture exceeded 16 MB")
        } catch ArchiveFailure.invalidListing {}
        let failed = try await ArchiveProcess.run(tool: perl, arguments: ["-e", "print 'bad';exit 5"], captureListing: true)
        require(failed.status == 5, "Failed listing was finished")
        do {
            _ = try await ArchiveProcess.run(tool: perl, arguments: ["-e", "print 'bad'"], captureListing: true)
            require(false, "Successful listing was not finished")
        } catch ArchiveFailure.invalidListing {}
        let signaled = try await ArchiveProcess.run(tool: perl, arguments: ["-e", "kill 15,$$"])
        require(signaled.status == 143, "Signal status did not preserve 128 + signal")
        print("PASS: archive binary bytes, exclusive output, expansion/capture limits, "
            + "rejected writes, listing finish, signal status")
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
