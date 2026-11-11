import Foundation

extension MonitorModule: NotchcastRegistrant {
    static let shared = MonitorModule(preferences: .shared, alertSink: {
        NotchcastHost.current.showMessage($0, .danger)
    }, fanFailure: {
        NotchcastHost.current.showMessage(String(localized: "Could not change fan mode.", table: "Notchcast"), .danger)
    })

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        // The hub sets the link channel before registrants run; without it there is no remote route.
        if let channel = RemoteFanModule.linkChannel { shared.registerRemoteFanRoute(on: channel) }
        let preferences = NotchcastPreferences.shared
        if !preferences.isOn(.systemMonitor) || !preferences.isOn(.fanControl) {
            shared.fans.restore(preservingPreference: true, silently: true)
        }
        return [.init(requires: [.systemMonitor], module: shared)]
    }
}
