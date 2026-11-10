import Foundation

extension LowDiskModule {
    nonisolated static let refreshCommand = NotchcastCommand(
        slug: "check-disk-space", name: String(localized: "Check Disk Space", table: "Notchcast"),
        sfSymbol: "internaldrive", feature: .lowDiskWarning,
        isEnabled: { NotchcastPreferences.shared.isOn(.island) && NotchcastPreferences.shared.isOn(.lowDiskWarning) },
        run: { LowDiskModule.shared.manager.refresh() })
}
