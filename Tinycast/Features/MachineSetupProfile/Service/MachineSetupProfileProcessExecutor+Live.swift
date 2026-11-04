import Darwin
import Foundation

extension MachineSetupProfileProcessExecutor {
    static func live() -> Self {
        Self(process: { executable, arguments in
            guard geteuid() != 0,
                  (executable == "/usr/bin/defaults"
                    && (arguments == ["read", "com.apple.dock", "autohide"]
                        || arguments == ["write", "com.apple.dock", "autohide", "-bool", "true"]))
                    || (executable == "/usr/bin/killall" && arguments == ["Dock"])
            else { throw Failure.unsupportedPayload }
            let task = Process()
            let output = Pipe()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            task.environment = ["PATH": "/usr/bin:/bin"]
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = output
            task.standardError = FileHandle.nullDevice
            try runToExit(task, timeout: 5)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            return Result(status: task.terminationStatus, output: String(bytes: data, encoding: .utf8) ?? "")
        }, isRoot: { geteuid() == 0 })
    }

    static func runToExit(_ task: Process, timeout: TimeInterval) throws {
        let finished = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in finished.signal() }
        try task.run()
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            if finished.wait(timeout: .now() + 0.25) == .timedOut {
                if task.isRunning { kill(task.processIdentifier, SIGKILL) }
                finished.wait()
            }
            throw Failure.stepFailed
        }
    }
}
