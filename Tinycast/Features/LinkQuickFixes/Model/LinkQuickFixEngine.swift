import Foundation

enum LinkQuickFixEngine {
    enum Cause: CaseIterable, Sendable {
        case dnsFailure, tailscaleStopped, mirrorStale, cableDown, linkExpiring
    }

    enum Action: Equatable, Sendable {
        case copyCommand(String)
        case openMirrorLog(URL)
        case openNetworkSettings
        case relinkInConnections
    }

    struct Configuration: Sendable {
        var mirrorSyncCommand: String?
        var mirrorLog: URL?
    }

    static func actions(for cause: Cause, configuration: Configuration) -> [Action] {
        switch cause {
        case .dnsFailure:
            [.copyCommand("sudo tailscale set --accept-dns=false\nsudo tailscale set --accept-dns=true")]
        case .tailscaleStopped:
            [.copyCommand("tailscale status\nsudo tailscale up")]
        case .mirrorStale:
            mirrorActions(configuration)
        case .cableDown:
            [.openNetworkSettings]
        case .linkExpiring:
            [.relinkInConnections]
        }
    }

    private static func mirrorActions(_ configuration: Configuration) -> [Action] {
        var actions: [Action] = []
        if let command = configuration.mirrorSyncCommand,
           !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            actions.append(.copyCommand(command))
        }
        if let log = configuration.mirrorLog, log.isFileURL {
            actions.append(.openMirrorLog(log))
        }
        return actions
    }
}
