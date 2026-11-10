import Foundation
import SystemConfiguration

enum RemoteScreenAddress {
    static func current() async throws -> RemoteScreenState.Availability {
        let request = ProcessRunner.Request(
            executable: URL(filePath: "/bin/launchctl"),
            arguments: ["print", "system/com.apple.screensharing"], timeout: .seconds(2))
        let enabled: Bool
        do { enabled = try await ProcessRunner.run(request).status == 0 } catch ProcessRunner.Failure.timedOut {
            enabled = false
        }
        guard enabled else { return .init(screenSharingEnabled: false) }
        guard let name = SCDynamicStoreCopyLocalHostName(nil) as String? else {
            throw RemoteScreenRequest.Failure.unavailable
        }
        return .init(screenSharingEnabled: true, host: name + ".local")
    }
}
