import ServiceManagement

enum LaunchAtLogin {
    /// Started by a LaunchAgent that keeps the app alive (Notchcast sets NOTCHCAST_LAUNCHD=1). The agent owns
    /// starting at login, so the login item stays off: both would start a second instance.
    static let managedByLaunchd = ProcessInfo.processInfo.environment["NOTCHCAST_LAUNCHD"] == "1"

    static var isEnabled: Bool {
        !managedByLaunchd && SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        let enabled = enabled && !managedByLaunchd
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("Tinycast: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}
