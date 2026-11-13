import Foundation

enum LinkQuickFixEngine {
    enum Cause: CaseIterable, Sendable {
        case dnsFailure, tailscaleStopped, cableDown, linkExpiring
    }

    enum Action: Equatable, Sendable {
        case copyCommand(String, cause: Cause)
        case openNetworkSettings
        case relinkInConnections
    }

    static func actions(for cause: Cause) -> [Action] {
        switch cause {
        case .dnsFailure:
            [.copyCommand("sudo tailscale set --accept-dns=false\nsudo tailscale set --accept-dns=true", cause: .dnsFailure)]
        case .tailscaleStopped:
            [.copyCommand("tailscale status\nsudo tailscale up", cause: .tailscaleStopped)]
        case .cableDown:
            [.openNetworkSettings]
        case .linkExpiring:
            [.relinkInConnections]
        }
    }
}
