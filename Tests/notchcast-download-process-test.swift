// notchcast-sources: Tinycast/Features/Notchcast/Process/ProcessRunner.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/ChildProcess.swift
// notchcast-sources: Tinycast/Features/Downloads/Service/DownloadToolLookup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Jobs/DownloadTool.swift
// notchcast-sources: Tinycast/Features/Downloads/Media/MediaOutput.swift
// notchcast-kit: platform
import AppKit
import Darwin
import Foundation
import Synchronization

@main struct DownloadsProcessTest {
    static func waitFor(_ condition: @Sendable () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "condition timed out")
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for quit in [false, true] {
            let pidFile = root.appending(path: "pid")
            let child = ChildProcess(executable: URL(filePath: "/bin/sh"), arguments: ["-c",
                #"trap '' TERM; sleep 30 & echo $! > "$1"; echo ready; wait"#, "test", pidFile.path])
            let ready = Mutex(false)
            let task = Task { try await child.run { _ in ready.withLock { $0 = true } } }
            try await waitFor { ready.withLock { $0 } }
            let pid = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
            if quit {
                NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
            } else {
                child.cancel()
            }
            do { _ = try await task.value; preconditionFailure("expected cancellation") } catch is CancellationError {}
            try await waitFor { kill(pid, 0) == -1 && errno == ESRCH }
        }
        let pidFile = root.appending(path: "orphan")
        let orphaning = ChildProcess(executable: URL(filePath: "/bin/sh"), arguments: ["-c",
            #"sh -c 'trap "" TERM; sleep 30 & echo $! > "$1"; wait' test "$1" & sleep .1; exit 0"#, "test", pidFile.path])
        let exited = try await orphaning.run()
        precondition(exited.status == 0)
        let orphan = Int32(try String(contentsOf: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))!
        try await waitFor { kill(orphan, 0) == -1 && errno == ESRCH }
        let escapedFile = root.appending(path: "escaped")
        let detaching = "use POSIX; if (fork()==0) { setsid(); open F, '>', $ARGV[0] or die; "
            + "print F $$; close F; sleep 30; exit; } "
            + "while (!-s $ARGV[0]) { select undef,undef,undef,.01; }"
        let escaped = ChildProcess(executable: URL(filePath: "/usr/bin/perl"), arguments: ["-e",
            detaching, escapedFile.path])
        let started = ContinuousClock.now
        _ = try await escaped.run()
        let escapedPID = Int32(try String(contentsOf: escapedFile, encoding: .utf8))!
        defer { kill(escapedPID, SIGKILL) }
        precondition(ContinuousClock.now - started < .seconds(5))
        precondition(kill(escapedPID, 0) == 0)
        kill(escapedPID, SIGKILL)
        try await waitFor { kill(escapedPID, 0) == -1 && errno == ESRCH }
        let signaled = try await ChildProcess(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "kill -TERM $$"]).run()
        precondition(signaled.status == 128 + SIGTERM)
        let progress = Mutex<MediaOutput.Progress?>(nil)
        let result = try await ChildProcess(executable: URL(filePath: "/bin/sh"), arguments: ["-c",
            "printf 'MEDIA_PROGRESS 50 100 NA 10 5\\r'; printf '%s' \"$PROBE\"; pwd; exit 7"],
            environment: ["PROBE": "exact:"], workingDirectory: root).run { line in
                if let value = MediaOutput.progress(line) { progress.withLock { $0 = value } }
            }
        precondition(result.status == 7 && result.output.contains("exact:/") && result.output.contains(root.lastPathComponent))
        precondition(progress.withLock { $0?.fraction } == 0.5)
        let cancelled = ChildProcess(executable: URL(filePath: "/bin/echo"), arguments: ["never"])
        cancelled.cancel()
        do { _ = try await cancelled.run(); preconditionFailure("pre-cancel") } catch is CancellationError {}
        print("PASS: cancellation, app quit, descendant cleanup after leader exit, progress, environment, cwd, exit, pre-cancel")
    }
}
