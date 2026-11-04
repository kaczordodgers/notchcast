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
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        }.value
        try Task.checkCancellation()
        guard enabled, let name = SCDynamicStoreCopyLocalHostName(nil) as String? else {
            throw RemoteScreenRequest.Failure.unavailable
        }
        return .init(screenSharingEnabled: true, host: name + ".local")
    }
}
