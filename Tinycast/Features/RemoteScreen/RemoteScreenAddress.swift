import Foundation
import SystemConfiguration

enum RemoteScreenAddress {
    static func current() async throws -> RemoteScreenState.Availability {
        let enabled = try await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/bin/launchctl")
            process.arguments = ["print", "system/com.apple.screensharing"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let exit = try process.runObservingExit()
            let timeout = DispatchWorkItem { @Sendable in
                if process.isRunning { process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2, execute: timeout)
            exit.wait()
            timeout.cancel()
            return process.terminationStatus == 0
        }.value
        try Task.checkCancellation()
        guard enabled else { return .init(screenSharingEnabled: false) }
        guard let name = SCDynamicStoreCopyLocalHostName(nil) as String? else {
            throw RemoteScreenRequest.Failure.unavailable
        }
        return .init(screenSharingEnabled: true, host: name + ".local")
    }
}
