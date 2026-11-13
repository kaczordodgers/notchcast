// notchcast-sources: Tinycast/Platform/SystemLanguages.swift Tinycast/Platform/SystemLanguages+Bundle.swift
// notchcast-sources: Tinycast/Features/ClearNotifications/Service/ClearNotificationsScript.swift
// notchcast-sources: Tinycast/Features/SystemTools/Model/NotificationCleanupPolicy.swift
import AppKit

@main struct LocalizationTests {
    static func main() {
        let keys = ["Clear Notifications…", "Clear All Notifications", "Clear All", "Close"]
        let polish = keys.map {
            SystemLanguages.localized($0, bundlePath: "/System/Library/CoreServices/NotificationCenter.app",
                                      languages: ["pl"])
        }
        precondition(polish == ["Wymaż powiadomienia…", "Wymaż wszystkie powiadomienia", "Wymaż wszystko", "Zamknij"])
        let source = ClearNotificationsScript.source(localized: polish)
        for name in polish + keys { precondition(source.contains(name)) }
        for strings in [polish, keys, Array(repeating: "quoted\"\\name\n", count: 4)] {
            let script = NSAppleScript(source: ClearNotificationsScript.source(localized: strings))!
            var error: NSDictionary?
            precondition(script.compileAndReturnError(&error), "\(String(describing: error))")
        }
        let handlers = String(source.components(separatedBy: "\non run").first!) + "\n"
        let checks = """
        on run
            return my matchesName("Name:Zamknij:123", {"Name:Zamknij", "Name:Close"}, true) and ¬
                my matchesName("Name:Close:123", {"Name:Zamknij", "Name:Close"}, true) and ¬
                my matchesName("Name:Wymaż wszystko:123", {"Name:Wymaż wszystko", "Name:Clear All"}, true) and ¬
                my matchesName("Name:Clear All:123", {"Name:Wymaż wszystko", "Name:Clear All"}, true) and ¬
                my matchesName("Wymaż wszystko", {"Wymaż wszystko", "Clear All"}, false) and ¬
                not my matchesName("Unrelated", {"Wymaż wszystko", "Clear All"}, false)
        end run
        """
        let script = NSAppleScript(source: handlers + checks)!
        var error: NSDictionary?
        precondition(script.compileAndReturnError(&error), "\(String(describing: error))")
        precondition(script.executeAndReturnError(&error).booleanValue, "\(String(describing: error))")
        let title = SystemLanguages.localized("Disk Not Ejected Properly",
            bundlePath: "/System/Library/Frameworks/DiskArbitration.framework", languages: ["pl"])
        precondition(title == "Dysk nie został wysunięty poprawnie.")
        let policy = NotificationCleanupPolicy(diskEjectionTitles: [title, "Disk Not Ejected Properly"],
            localizedClose: polish[3], localizedClearAll: polish[2])
        for name in [title, "Disk Not Ejected Properly"] {
            precondition(policy.closeAction(for: .init(identifier: name, title: name,
                isIndividualAlert: true, actions: ["AXClose"])) == "AXClose")
        }
        precondition(policy.isStack(actions: ["Name:Wymaż wszystko…", "AXClose"]),
            "localized Clear All marks a notification stack")
        precondition(policy.closeAction(for: .init(identifier: title, title: title,
            isIndividualAlert: true, actions: ["Name:Zamknij…"])) == "Name:Zamknij…")
        print("Verified macOS Polish strings, Polish and English script matching, and disk title selection")
    }
}
