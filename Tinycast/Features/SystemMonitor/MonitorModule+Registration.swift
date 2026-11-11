import Foundation

extension MonitorModule: NotchcastRegistrant {
    static let shared = MonitorModule(preferences: .shared, alertSink: {
        NotchcastHost.current.showMessage($0, .danger)
    }, fanFailure: {
        NotchcastHost.current.showMessage(String(localized: "Could not change fan mode.", table: "Notchcast"), .danger)
    })

    static func register(_ core: AppCore) -> [NotchcastModuleController.Entry] {
        [.init(requires: [.systemMonitor], module: shared)]
    }
}
