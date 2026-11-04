import Foundation

extension RemoteFanModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "remote-fans", name: String(localized: "Other Mac Fans"), sfSymbol: "fan", feature: .machMBPFans,
        isEnabled: { [.machLink, .machMBPFans].allSatisfy { NotchcastPreferences.shared.isOn($0) } },
        run: { Task { do {
            let report = try await NotchcastCore.remoteFans.run(.cycle)
            let mode: String = switch report.mode {
            case .auto: String(localized: "Automatic")
            case .mid: String(localized: "Medium")
            case .max: String(localized: "Maximum")
            }
            NotchcastCore.remoteResult(String(localized: "Fan mode: \(mode)"))
        } catch { NotchcastCore.remoteResult(String(localized: "Could not change fan mode.")) } } })
}
