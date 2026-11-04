import Foundation

extension FanControl {
    nonisolated static let maxCommand = NotchcastCommand(
        slug: "fans-max", name: String(localized: "Set Fans to Max"), sfSymbol: "fan",
        isEnabled: { NotchcastPreferences.shared.isOn(.systemMonitor)
            && NotchcastPreferences.shared.isOn(.fanControl) },
        run: { NotchcastCore.setFanMode(.max) })

    nonisolated static let autoCommand = NotchcastCommand(
        slug: "fans-auto", name: String(localized: "Set Fans to Auto"), sfSymbol: "fan",
        isEnabled: { NotchcastPreferences.shared.isOn(.systemMonitor)
            && NotchcastPreferences.shared.isOn(.fanControl) },
        run: { NotchcastCore.setFanMode(.auto) })
}
