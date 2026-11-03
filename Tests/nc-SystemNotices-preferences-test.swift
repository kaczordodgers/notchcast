import Foundation

@main
struct SystemNoticesPreferencesTest {
    @MainActor static func main() {
        let suite = "notices-preferences-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = SystemNoticesPreferences(defaults: defaults)
        precondition(preferences.wifi && preferences.tailscale && preferences.battery)
        preferences.wifi = false
        precondition(!preferences.allows(.wifi(available: true)))
        precondition(preferences.allows(.tailscale(.connected)))
        preferences.tailscale = false
        preferences.battery = false
        let restored = SystemNoticesPreferences(defaults: defaults)
        precondition(!restored.wifi && !restored.tailscale && !restored.battery)
        precondition(!restored.allows(.lowBattery(percent: 10, threshold: 10)))
        print("PASS notice defaults, live filtering and isolated persistence")
    }
}
