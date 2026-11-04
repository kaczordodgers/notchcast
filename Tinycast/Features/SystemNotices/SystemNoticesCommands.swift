import Foundation

extension SystemNoticesModule {
    nonisolated static let refreshCommand = NotchcastCommand(
        slug: "check-tailscale", name: String(localized: "Check Tailscale Status"), sfSymbol: "network",
        isEnabled: { NotchcastPreferences.shared.isOn(.island) && NotchcastPreferences.shared.isOn(.systemNotices) },
        run: { NotchcastCore.systemNotices.manager.refreshTailscale() })
}
