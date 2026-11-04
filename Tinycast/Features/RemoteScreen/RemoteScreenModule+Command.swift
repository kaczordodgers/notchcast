import Foundation

extension RemoteScreenModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "remote-screen", name: String(localized: "Remote Screen"), sfSymbol: "display", feature: .remoteScreen,
        isEnabled: { [.machLink, .remoteScreen].allSatisfy { NotchcastPreferences.shared.isOn($0) } },
        run: { Task { do {
            try await NotchcastCore.remoteScreen.coordinator.show(.init(host: "peer.local"), preferredClientInstalled: false)
        } catch {
            let message = switch error {
            case RemoteScreenRequest.Failure.peerDisabled: String(localized: "Remote Screen is off on the other Mac.")
            case RemoteScreenRequest.Failure.sharingDisabled: String(localized: "Screen Sharing is off on the other Mac.")
            default: String(localized: "Could not reach the other Mac.")
            }
            NotchcastCore.remoteResult(message)
        } } })
}
