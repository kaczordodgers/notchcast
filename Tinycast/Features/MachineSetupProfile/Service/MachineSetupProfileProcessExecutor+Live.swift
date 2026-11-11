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
            let url = URL(fileURLWithPath: executable)
            let request = ProcessRunner.Request(
                executable: url, arguments: arguments,
                environment: ExecutableLocator.environment(running: url, inherited: [:]), timeout: .seconds(5))
            do {
                let output = try ProcessRunner.runBlocking(request)
                return Result(status: output.status, output: String(bytes: output.stdout, encoding: .utf8) ?? "")
            } catch ProcessRunner.Failure.timedOut {
                throw Failure.stepFailed
            }
        }, isRoot: { geteuid() == 0 })
    }
}
