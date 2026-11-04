// notchcast-sources: Tinycast/Features/MachRemote/Model/*.swift
// notchcast-sources: Tinycast/Features/MachRemote/Integration/RemoteMacScreenModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation

@main @MainActor
struct RemoteScreenTest {
    static func main() {
        let suite = "screen-test." + UUID().uuidString
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let preferences = NotchcastPreferences(suiteName: suite)
        var opened: [URL] = []
        var notices: [String] = []
        let module = RemoteMacScreenModule(preferences: preferences,
            open: { opened.append($0) }, post: { notices.append($0) })
        precondition(!preferences.isOn(.remoteMacScreen))
        precondition(!NotchcastFeature.remoteMacScreen.needsIsland)
        precondition(NotchcastFeature.remoteMacScreen.settingsGroup == NotchcastFeature.machRemote.settingsGroup)
        module.openScreen()
        precondition(opened.isEmpty && notices.isEmpty)
        preferences.set(.remoteMacScreen, true)
        for (address, expected) in [("fake-mac", "vnc://fake-mac"),
                                    ("user@fake-mac", "vnc://user@fake-mac"),
                                    ("2001:db8::1", "vnc://[2001:db8::1]"),
                                    ("user@::1", "vnc://user@[::1]")] {
            preferences.remoteMacAddress = address
            module.openScreen()
            precondition(opened.last?.absoluteString == expected)
        }
        for address in ["", "-bad", "host/path", "host:5900", "@host", "user@", "a@b@c"] {
            preferences.remoteMacAddress = address
            module.openScreen()
            precondition(notices.last == String(localized: "Set the remote Mac address in Settings"))
        }
        precondition(opened.count == 4 && notices.count == 7)
        preferences.set(.remoteMacScreen, false)
        module.openScreen()
        precondition(opened.count == 4 && notices.count == 7)
    }
}
