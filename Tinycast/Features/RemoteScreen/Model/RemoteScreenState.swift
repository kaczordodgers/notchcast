import Foundation

enum RemoteScreenState: Equatable, Sendable {
    case disabled, idle, checking(UUID), ready, opening, opened, failed

    enum Client: String, Codable, Sendable {
        case preferred, apple

        var bundleID: String {
            switch self {
            case .preferred: "io.nekohasekai.screensharing"
            case .apple: "com.apple.ScreenSharing"
            }
        }
    }

    struct Availability: Codable, Sendable {
        let screenSharingEnabled: Bool
        var host: String? = nil
        var peerEnabled: Bool?
    }
}
