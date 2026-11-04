import Foundation

extension RemoteScreenModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "remote-screen", name: String(localized: "Remote Screen"), sfSymbol: "display", feature: .remoteScreen,
        isEnabled: { [.machLink, .remoteScreen].allSatisfy { NotchcastPreferences.shared.isOn($0) } },
        run: { Task { do { try await NotchcastCore.remoteScreen.coordinator.show(.init(host: "peer.local"), preferredClientInstalled: false) } catch { NotchcastCore.remoteResult(String(localized: "Remote Screen")) } } })
}
