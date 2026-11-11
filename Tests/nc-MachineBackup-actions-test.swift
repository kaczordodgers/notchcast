// notchcast-sources: Tinycast/Features/MachineBackup/Model/*.swift Tinycast/Features/MachineBackup/Service/*.swift
// notchcast-kit: platform core
import Foundation
import Synchronization

private final class FakeBackupTooling: MachineBackupTooling {
    struct State {
        var requests: [MachineBackupRequest] = []
        var response = Data()
        var failure: MachineBackupFailure?
        var suspended = false
        var waiter: CheckedContinuation<Data, Error>?
    }
    let state = Mutex(State())

    func run(_ request: MachineBackupRequest) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            state.withLock {
                $0.requests.append(request)
                if $0.suspended {
                    $0.waiter = continuation
                } else if let failure = $0.failure {
                    continuation.resume(throwing: failure)
                } else {
                    continuation.resume(returning: $0.response)
                }
            }
        }
    }

    func complete() {
        state.withLock {
            $0.waiter?.resume(returning: $0.response)
            $0.waiter = nil
        }
    }
}

@main
struct MachineBackupActionsTest {
    static let snapshot = String(repeating: "a", count: 64)

    @MainActor
    static func main() async throws {
        let home = URL(fileURLWithPath: "/Users/fixture", isDirectory: true)
        let configuration = configuration(home: home)
        try commandChecks(configuration)
        try targetChecks()
        try await coordinatorChecks(configuration)
        try await runnerChecks()
        print("PASS: backup plans, JSON, restore safety, preferences, serialization and stale-result cancellation")
    }

    static func configuration(home: URL) -> MachineBackupConfiguration {
        MachineBackupConfiguration(jobLabel: "test.backup", userID: 501,
                                   resticExecutable: URL(fileURLWithPath: "/fixture/restic"),
                                   repository: "sftp:fixture:/repository", host: "fixture",
                                   passwordCommand: "/fixture/keychain-command", homeDirectory: home)
    }

    static func expect(_ expected: MachineBackupFailure, _ body: () throws -> Void) throws {
        do {
            try body()
            fatalError("Expected \(expected)")
        } catch let failure as MachineBackupFailure { precondition(failure == expected, "\(failure) != \(expected)") }
    }

    static func commandChecks(_ configuration: MachineBackupConfiguration) throws {
        let start = try MachineBackupPolicy.runNow(configuration)
        precondition(start.executable.path == "/bin/launchctl")
        precondition(start.arguments == ["kickstart", "gui/501/test.backup"])
        precondition(!start.arguments.contains("-k"))
        let list = try MachineBackupPolicy.snapshots(configuration)
        precondition(list.arguments == ["--no-cache", "snapshots", "--host", "fixture", "--json"])
        precondition(list.environment["RESTIC_PASSWORD_COMMAND"] == "/fixture/keychain-command")
        precondition(list.environment["RESTIC_PASSWORD"] == nil)
        let source = "/Users/fixture/Documents/file with spaces.txt"
        let target = configuration.downloadsDirectory.appendingPathComponent("Restored-test", isDirectory: true)
        let restore = try MachineBackupPolicy.restore(configuration, snapshot: snapshot, path: source, target: target)
        precondition(restore.arguments == ["--no-cache", "restore", snapshot, "--include", source,
                                          "--target", target.path, "--overwrite", "never"])
        precondition(!restore.arguments.contains("--delete"))
        precondition(restore.restoreTarget == target)
        for identifier in ["latest", "--help", snapshot + ":/", "../bad", "abc"] {
            try expect(.invalidSnapshot) { _ = try MachineBackupPolicy.browse(configuration, snapshot: identifier, path: "/") }
        }
        for path in ["relative", "/Users/fixture/../Library", "/Users/fixture/./file", "/Users/fixture/a\0b"] {
            try expect(.invalidPath) { _ = try MachineBackupPolicy.browse(configuration, snapshot: snapshot, path: path) }
        }
        for path in ["/System", "/Library/file", "/Users/fixture-old/file", "/Users/fixture/a*", "/Users/fixture/a[1]"] {
            try expect(.invalidPath) {
                _ = try MachineBackupPolicy.restore(configuration, snapshot: snapshot, path: path, target: target)
            }
        }
        for path in ["/System/Restored", "/Library/Restored", "/Users/fixture/Documents/Restored",
                     "/Users/fixture/Downloads", "/Users/fixture/Downloads/.hidden",
                     "/Users/fixture/Downloads/../Restored"] {
            try expect(.unsafeTarget) {
                _ = try MachineBackupPolicy.restore(configuration, snapshot: snapshot, path: source,
                                                     target: URL(fileURLWithPath: path))
            }
        }
        try expect(.unsafeTarget) {
            try MachineBackupPolicy.validateTarget(URL(fileURLWithPath: "/System/Downloads/Restored"),
                                                    home: URL(fileURLWithPath: "/System"))
        }
        let json = """
        [{"id":"\(snapshot)","time":"2026-11-01T12:00:00Z","hostname":"fixture","paths":["/Users/fixture"]},
         {"id":"\(String(repeating: "b", count: 64))","time":"2026-11-02T12:00:00Z","hostname":"other","paths":[]}]
        """
        let snapshots = try MachineBackupPolicy.decodeSnapshots(Data(json.utf8), host: "fixture")
        precondition(snapshots.count == 1 && snapshots[0].id == snapshot)
        let datedJSON = """
        [{"id":"\(snapshot)","time":"2026-11-01T12:00:00Z","hostname":"fixture","paths":[]},
         {"id":"\(String(repeating: "c", count: 64))","time":"2026-11-01T12:00:00.1Z","hostname":"fixture","paths":[]}]
        """
        let dated = try MachineBackupPolicy.decodeSnapshots(Data(datedJSON.utf8), host: "fixture")
        precondition(dated[0].id == String(repeating: "c", count: 64))
        let nodes = try MachineBackupPolicy.decodeNodes(Data("""
        {"struct_type":"snapshot","id":"\(snapshot)"}
        {"struct_type":"node","name":"file.txt","path":"/Users/fixture/file.txt","type":"file","size":12}
        {"struct_type":"node","name":"folder","path":"/Users/fixture/folder","type":"dir"}
        """.utf8))
        precondition(nodes.count == 2 && nodes[0].size == 12 && nodes[1].size == nil)
        try expect(.invalidResponse) { _ = try MachineBackupPolicy.decodeSnapshots(Data("bad".utf8), host: "fixture") }
        try expect(.invalidResponse) { _ = try MachineBackupPolicy.decodeNodes(Data("bad".utf8)) }
        try expect(.invalidResponse) { _ = try MachineBackupPolicy.decodeNodes(Data("{}".utf8)) }
    }

    static func targetChecks() throws {
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("nc-backup-test-" + UUID().uuidString, isDirectory: true)
        let home = root.appendingPathComponent("home", isDirectory: true)
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let files = FileManager.default
        try files.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        let target = downloads.appendingPathComponent("Restored-test", isDirectory: true)
        try MachineBackupRunner.reserveRestoreTarget(target, home: home)
        let marker = target.appendingPathComponent("untouched.txt")
        try Data("original".utf8).write(to: marker)
        try expect(.targetExists) { try MachineBackupRunner.reserveRestoreTarget(target, home: home) }
        let contents = try Data(contentsOf: marker)
        precondition(contents == Data("original".utf8))
        let existingFile = downloads.appendingPathComponent("Restored-file")
        try Data("existing".utf8).write(to: existingFile)
        try expect(.targetExists) { try MachineBackupRunner.reserveRestoreTarget(existingFile, home: home) }
        let symlink = downloads.appendingPathComponent("Restored-link")
        try files.createSymbolicLink(at: symlink, withDestinationURL: target)
        try expect(.targetExists) { try MachineBackupRunner.reserveRestoreTarget(symlink, home: home) }
        let dangling = downloads.appendingPathComponent("Restored-dangling")
        try files.createSymbolicLink(at: dangling, withDestinationURL: root.appendingPathComponent("missing"))
        try expect(.targetExists) { try MachineBackupRunner.reserveRestoreTarget(dangling, home: home) }
        let otherHome = root.appendingPathComponent("other", isDirectory: true)
        try files.createDirectory(at: otherHome, withIntermediateDirectories: false)
        try files.createSymbolicLink(at: otherHome.appendingPathComponent("Downloads"), withDestinationURL: downloads)
        try expect(.unsafeTarget) {
            try MachineBackupRunner.reserveRestoreTarget(
                otherHome.appendingPathComponent("Downloads/Restored-escape"), home: otherHome)
        }
    }

    @MainActor
    static func coordinatorChecks(_ configuration: MachineBackupConfiguration) async throws {
        let suite = "nc-backup-test-" + UUID().uuidString
        let preferences = NotchcastPreferences(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        preferences.set(.backupRunNow, true) // hidden switches read off until set
        preferences.set(.backupBrowseRestore, true)
        let fake = FakeBackupTooling()
        let coordinator = MachineBackupCoordinator(tooling: fake, preferences: preferences)
        coordinator.start()
        do { try await coordinator.runNow(); fatalError("Unconfigured") } catch let failure as MachineBackupFailure {
            precondition(failure == .configuration)
        }
        try coordinator.configure(configuration)
        preferences.set(.backupRunNow, false)
        do { try await coordinator.runNow(); fatalError("Disabled") } catch let failure as MachineBackupFailure {
            precondition(failure == .disabled)
        }
        precondition(fake.state.withLock { $0.requests.isEmpty })
        preferences.set(.backupRunNow, true)
        try await coordinator.runNow()
        precondition(fake.state.withLock { $0.requests.count == 1 })
        fake.state.withLock { $0.response = Data("[]".utf8) }
        try await coordinator.refreshSnapshots()
        precondition(coordinator.snapshots.isEmpty)
        fake.state.withLock {
            $0.response = Data("""
            {"struct_type":"snapshot"}
            {"struct_type":"node","name":"file.txt","path":"/Users/fixture/file.txt","type":"file","size":12}
            """.utf8)
        }
        try await coordinator.browse(snapshot: snapshot, path: "/Users/fixture")
        precondition(coordinator.nodes.count == 1)
        let target = configuration.downloadsDirectory.appendingPathComponent("Restored-fixture", isDirectory: true)
        try await coordinator.restore(snapshot: snapshot, path: "/Users/fixture/file.txt", target: target)
        precondition(coordinator.lastRestoreTarget == target)
        precondition(fake.state.withLock { $0.requests.last?.restoreTarget == target })
        fake.state.withLock { $0.response = Data("[]".utf8) }
        fake.state.withLock { $0.failure = .toolFailed(11) }
        do {
            try await coordinator.refreshSnapshots()
            fatalError("Locked repository")
        } catch let failure as MachineBackupFailure {
            precondition(failure == .toolFailed(11))
        }
        precondition(!coordinator.isBusy)
        fake.state.withLock { $0.failure = nil; $0.suspended = true }
        let pending = Task { try await coordinator.refreshSnapshots() }
        while !fake.state.withLock({ $0.waiter != nil }) { await Task.yield() }
        do { try await coordinator.runNow(); fatalError("Concurrent operation") } catch let failure as MachineBackupFailure {
            precondition(failure == .busy)
        }
        coordinator.stop()
        coordinator.start()
        fake.complete()
        do { try await pending.value; fatalError("Stale response") } catch is CancellationError {}
        precondition(!coordinator.isBusy && coordinator.snapshots.isEmpty)
        let cancelled = Task { try await coordinator.refreshSnapshots() }
        while !fake.state.withLock({ $0.waiter != nil }) { await Task.yield() }
        cancelled.cancel()
        fake.complete()
        do { try await cancelled.value; fatalError("Caller cancelled") } catch is CancellationError {}
        precondition(!coordinator.isBusy)
        let switchedOff = Task { try await coordinator.refreshSnapshots() }
        while !fake.state.withLock({ $0.waiter != nil }) { await Task.yield() }
        preferences.set(.backupBrowseRestore, false)
        await Task.yield()
        preferences.set(.backupBrowseRestore, true)
        fake.complete()
        do { try await switchedOff.value; fatalError("Feature switched off") } catch is CancellationError {}
    }

    static func runnerChecks() async throws {
        let runner = MachineBackupRunner()
        let request = MachineBackupRequest(executable: URL(fileURLWithPath: "/usr/bin/printf"),
                                           arguments: ["fixture output"])
        let response = try await runner.run(request)
        precondition(response == Data("fixture output".utf8))
        let path = try await runner.run(.init(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo $PATH"]))
        precondition(path == Data("/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin\n".utf8), "System ssh before Homebrew's")
        let failure = MachineBackupRequest(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [])
        do { _ = try await runner.run(failure); fatalError("Process failure") } catch let error as MachineBackupFailure {
            precondition(error == .toolFailed(1))
        }
        let sleeper = MachineBackupRequest(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"])
        let pending = Task { try await runner.run(sleeper) }
        try await Task.sleep(for: .milliseconds(100))
        pending.cancel()
        do { _ = try await pending.value; fatalError("Process cancellation") } catch is CancellationError {}
        let flood = MachineBackupRequest(executable: URL(fileURLWithPath: "/usr/bin/head"),
                                         arguments: ["-c", "16777217", "/dev/zero"])
        do { _ = try await runner.run(flood); fatalError("Output cap") } catch let error as MachineBackupFailure {
            precondition(error == .outputLimit)
        }
    }
}
