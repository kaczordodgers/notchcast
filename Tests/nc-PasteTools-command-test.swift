// notchcast-sources: Tinycast/Features/PasteTools/Service/PlainPasteModule+Command.swift
// notchcast-kit: command
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
import Foundation

@MainActor final class PlainPasteModule {
    var pastes = 0
    func paste() { pastes += 1 }
}

@MainActor enum NotchcastCore {
    static let pastePlain: PlainPasteModule? = PlainPasteModule()
}

enum NotchcastFeature { case pastePlain }

@main @MainActor struct PlainPasteCommandTest {
    static func main() {
        NotchcastPreferences.shared.enabled = false
        let command = PlainPasteModule.launcherCommand
        precondition(!command.isEnabled())
        NotchcastPreferences.shared.enabled = true
        precondition(command.isEnabled())
        command.run()
        precondition(NotchcastCore.pastePlain?.pastes == 1)
        print("PASS: plain-paste command availability and dispatch; fake paste target only")
    }
}
