// notchcast-new-switch-ids: systemPage
// notchcast-addon-order: 260
// notchcast-readme: Mac Tweaks: System in the Island shows CPU, memory, disk and network, warns when hot and ejects disks
import Foundation

/// The System page in the island (#977): four tiles, the busiest processes and a hot warning; off by default.
enum SystemMonitorAddon: NotchcastAddon {
    static let switches = [
        NotchcastSwitch(
            id: "systemPage",
            title: String(localized: "System in the Island", table: "NotchcastSystemMonitor"),
            subtitle: String(
                localized: "CPU, memory, disk and network on a page in the island, with a warning when one runs hot.",
                table: "NotchcastSystemMonitor"),
            category: .macTweaks),
    ]

    static func makeModule(_ context: NotchcastContext) -> (any NotchcastModule)? {
        SystemMonitorModule(context: context, system: .live())
    }
}
