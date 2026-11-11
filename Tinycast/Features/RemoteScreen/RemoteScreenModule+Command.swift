import Foundation

extension RemoteScreenModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "remote-screen", name: String(localized: "Remote Screen", table: "Notchcast"), sfSymbol: "display", feature: .remoteScreen,
        run: { Task { do {
            try await RemoteScreenModule.shared?.coordinator.show(.init(host: "peer.local"), preferredClientInstalled: false)
        } catch {
            let message = switch error {
            case RemoteScreenRequest.Failure.peerDisabled: String(localized: "Remote Screen is off on the other Mac.", table: "Notchcast")
            case RemoteScreenRequest.Failure.sharingDisabled: String(localized: "Screen Sharing is off on the other Mac.", table: "Notchcast")
            default: String(localized: "Could not reach the other Mac.", table: "Notchcast")
            }
            NotchcastHost.current.remoteResult(message)
        } } })
}
