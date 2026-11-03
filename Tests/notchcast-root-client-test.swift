// notchcast-sources: -parse-as-library Tinycast/Features/Notchcast/Root/*.swift Tinycast/Platform/ProcessExit.swift
import Darwin
import Foundation

@main
struct RootClientTest {
    static func main() async throws {
        validateCommands()
        try validateExecutable()
        try validatePaths()
        try await validateProcessLifetime()
        print("PASS: root commands, replies, path ownership and permissions, timeouts and cancellation")
    }

    private static func validateCommands() {
        for command in RootContract.Command.allCases {
            precondition(RootContract.Command(arguments: command.arguments) == command)
            precondition(command.operation.timeout == .seconds(3))
            precondition(RootContract.Reply(command: command, output: command.output) != nil)
            precondition(RootContract.Reply(command: command, output: command.output + "extra") == nil)
        }
        let invalid: [[String]] = [
            [], [""], ["evil"], ["--help"], ["VERSION"], ["version", "extra"],
            ["ping", "extra"], ["version;id"], ["$(id)"], ["/bin/sh"], ["ping\n"],
            ["charging", "on"], ["sleep", "disable"], ["fan", "set", "1"], ["version\0"],
        ]
        for arguments in invalid {
            precondition(RootContract.Command(arguments: arguments) == nil)
        }
        precondition(RootContract.Reply(command: .version, output: "2\n") == nil)
        precondition(RootContract.Reply(command: .ping, output: "pong") == nil)
        precondition(RootContract.Operation.change.timeout == .seconds(12))
    }

    private static func validateExecutable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchcast-helper-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let helper = directory.appendingPathComponent("helper")
        let sources = try FileManager.default.contentsOfDirectory(atPath: "notchcast/root")
            .filter { $0.hasSuffix(".swift") }.sorted().map { "notchcast/root/\($0)" }
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["swiftc", "-swift-version", "6", "-O"] + sources + ["-o", helper.path]
        try compiler.run()
        compiler.waitUntilExit()
        precondition(compiler.terminationStatus == 0, "Helper compilation failed")

        let cases: [([String], Int32, String)] = [
            (["version"], 0, "1\n"), (["ping"], 0, "pong\n"),
            ([], 64, ""), (["unknown"], 64, ""), (["version", "extra"], 64, ""),
            (["ping", "extra"], 64, ""),
        ]
        for (arguments, status, expected) in cases {
            let process = Process()
            let output = Pipe()
            let errors = Pipe()
            process.executableURL = helper
            process.arguments = arguments
            process.environment = ["PATH": "/nonexistent", "NOTCHCAST_COMMAND": "unknown"]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            process.waitUntilExit()
            precondition(process.terminationReason == .exit && process.terminationStatus == status)
            precondition(output.fileHandleForReading.readDataToEndOfFile() == Data(expected.utf8))
            precondition(errors.fileHandleForReading.readDataToEndOfFile().isEmpty)
        }
        print("PASS: compiled helper version=1, ping=pong, invalid arguments exit 64 silently")
    }

    private static func validatePaths() throws {
        precondition(getuid() != 0, "Run this harness as your ordinary user")
        precondition(RootToolPath.verify("/usr/bin/true") == nil)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchcast-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("helper")
        try Data("fixture".utf8).write(to: file)
        precondition(chmod(file.path, 0o755) == 0)
        precondition(RootToolPath.check(file.path, directory: false) == .wrongOwner(file.path))
        precondition(RootToolPath.check(directory.path, directory: true) == .wrongOwner(directory.path))
        precondition(RootToolPath.verify(file.path) != nil)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        precondition(RootToolPath.check(link.path, directory: false) == .wrongKind(link.path))
        let absent = directory.appendingPathComponent("absent").path
        precondition(RootToolPath.check(absent, directory: false) == .missing(absent))
        for path in ["relative/helper", "/", "/Library//helper", "/Library/../helper", "/Library/./helper"] {
            precondition(RootToolPath.verify(path) == .wrongKind(path))
        }

        var info = stat()
        info.st_uid = 0
        info.st_mode = S_IFREG | 0o755
        precondition(RootToolPath.problem(path: "helper", info: info, directory: false) == nil)
        for permissions: mode_t in [0o775, 0o757, 0o777] {
            info.st_mode = S_IFREG | permissions
            precondition(RootToolPath.problem(path: "helper", info: info, directory: false) == .writable("helper"))
        }
        info.st_mode = S_IFREG | 0o644
        precondition(RootToolPath.problem(path: "helper", info: info, directory: false) == .notExecutable("helper"))
        info.st_mode = S_IFDIR | 0o755
        precondition(RootToolPath.problem(path: "parent", info: info, directory: true) == nil)
        info.st_mode = S_IFDIR | 0o775
        precondition(RootToolPath.problem(path: "parent", info: info, directory: true) == .writable("parent"))
        info.st_mode = S_IFLNK | 0o755
        precondition(RootToolPath.problem(path: "parent", info: info, directory: true) == .wrongKind("parent"))
    }

    private static func validateProcessLifetime() async throws {
        let fast = sleeper("0.01")
        let fastExit = try fast.runObservingExit()
        try await RootHelperClient.wait(for: fast, exit: fastExit, timeout: .seconds(1))
        precondition(!fast.isRunning && fast.terminationStatus == 0)

        let slow = sleeper("10")
        let slowExit = try slow.runObservingExit()
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await RootHelperClient.wait(for: slow, exit: slowExit, timeout: .milliseconds(50))
            preconditionFailure("A slow helper must time out")
        } catch RootHelperClient.Failure.timedOut {
            precondition(!slow.isRunning)
            precondition(start.duration(to: clock.now) < .seconds(2))
        }

        let cancelled = sleeper("10")
        let cancelledExit = try cancelled.runObservingExit()
        let task = Task {
            try await RootHelperClient.wait(for: cancelled, exit: cancelledExit, timeout: .seconds(3))
        }
        task.cancel()
        do {
            try await task.value
            preconditionFailure("Cancellation must propagate")
        } catch is CancellationError {
            precondition(!cancelled.isRunning)
        }
    }

    private static func sleeper(_ seconds: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = [seconds]
        process.environment = [:]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}
