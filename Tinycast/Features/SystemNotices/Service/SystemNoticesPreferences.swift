import Foundation
import Observation

@MainActor @Observable
final class SystemNoticesPreferences {
    var wifi: Bool { didSet { defaults.set(wifi, forKey: "notchcast.notices.wifi") } }
    var tailscale: Bool { didSet { defaults.set(tailscale, forKey: "notchcast.notices.tailscale") } }
    var battery: Bool { didSet { defaults.set(battery, forKey: "notchcast.notices.battery") } }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName:
         (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")!) {
        self.defaults = defaults
        wifi = defaults.object(forKey: "notchcast.notices.wifi") as? Bool ?? true
        tailscale = defaults.object(forKey: "notchcast.notices.tailscale") as? Bool ?? true
        battery = defaults.object(forKey: "notchcast.notices.battery") as? Bool ?? true
    }

    func allows(_ notice: SystemNoticeEngine.Notice) -> Bool {
        switch notice {
        case .wifi: wifi
        case .tailscale: tailscale
        case .lowBattery: battery
        }
    }
}
