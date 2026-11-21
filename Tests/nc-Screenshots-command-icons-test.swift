// notchcast-kit: notchcast-command-icons
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/ScreenshotsAddon.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Model/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotSystem.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScreenshotOutput.swift
// notchcast-sources: Tinycast/Features/Notchcast/Screenshots/Service/ScrollingCaptureRun.swift
// notchcast-reads: Tinycast/Features/Notchcast/NotchcastCore.swift
import SwiftUI

@main
@MainActor
enum ScreenshotsCommandIconTests {
    static func main() { NotchcastCommandIconCheck.run(ScreenshotsAddon.self) }
}

// The shipped `live` system and settings UI are left out: these stand in so the descriptor compiles.
struct ScreenshotsSettingsView: View {
    init(defaults: UserDefaults) {}
    var body: some View { EmptyView() }
}
extension ScreenshotSystem {
    static var live: Self { fatalError("the harness never makes a module") }
}
