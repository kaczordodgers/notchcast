import Darwin
import Foundation

extension MachineSetupProfileProcessExecutor {
    static func live() -> Self {
        Self(process: { executable, arguments in
            guard geteuid() != 0, executable == "/usr/bin/defaults",
                  arguments == ["read", "com.apple.dock", "autohide"]
                    || arguments == ["write", "com.apple.dock", "autohide", "-bool", "true"]
            else { throw Failure.unsupportedPayload }
            let task = Process()
            let output = Pipe()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            task.environment = ["PATH": "/usr/bin:/bin"]
            task.standardInput = FileHandle.nullDevice
            task.standardOutput = output
            task.standardError = FileHandle.nullDevice
            try task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return Result(status: task.terminationStatus, output: String(bytes: data, encoding: .utf8) ?? "")
        }, isRoot: { geteuid() == 0 })
    }
}
