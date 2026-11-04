import Foundation

extension RemoteFanModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "remote-fans", name: String(localized: "Other Mac Fans"), sfSymbol: "fan", feature: .machMBPFans,
        isEnabled: { [.machLink, .machMBPFans].allSatisfy { NotchcastPreferences.shared.isOn($0) } },
        run: { Task { do { _ = try await NotchcastCore.remoteFans.run(.cycle) } catch { NotchcastCore.remoteResult(String(localized: "Could not change fan mode.")) } } })
}
