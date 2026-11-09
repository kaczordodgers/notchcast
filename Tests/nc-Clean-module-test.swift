// notchcast-sources: Tinycast/Features/Clean/*/*.swift Tinycast/Features/Clean/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-kit: root platform
import Foundation

enum AppPaths {
    static func applicationSupport() -> URL { FileManager().temporaryDirectory }
}

struct DialogAction {
    enum Role { case destructive, cancel }
    let title: String
    let role: Role
}

@MainActor final class AppCore {
    enum Tone { case danger }
    func showMessage(_ message: String, tone: Tone) { preconditionFailure(message) }
    func choose(title: String, message: String, symbol: String, options: [DialogAction],
                defaultIndex: Int, tone: Tone) async -> Int { defaultIndex }
}

enum NotchcastCore {}

@main struct CleanModuleTests {
    @MainActor static func main() {
        let module = CleanModule()
        module.start()
        precondition(module.coordinator.helperCurrent)
        module.stop()
        module.start()
        precondition(module.coordinator.helperCurrent)
        module.stop()
        print("PASS: Scan remains reachable across module restarts for helper version rechecks")
    }
}
