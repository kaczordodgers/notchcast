import Foundation

extension RemoteFanModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "remote-fans", name: String(localized: "Other Mac Fans", table: "Notchcast"), sfSymbol: "fan", feature: .machMBPFans,
        run: { Task { do {
            guard let module = RemoteFanModule.shared else { throw RemoteFanReport.Failure.unavailable }
            let report = try await module.run(.cycle)
            let mode: String = switch report.mode {
            case .auto: String(localized: "Automatic")
            case .mid: String(localized: "Medium")
            case .max: String(localized: "Maximum")
            }
            NotchcastHost.current.remoteResult(String(localized: "Fan mode: \(mode)", table: "Notchcast"))
        } catch { NotchcastHost.current.remoteResult(String(localized: "Could not change fan mode.", table: "Notchcast")) } } })
}
