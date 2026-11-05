// notchcast-sources: Tinycast/Features/PasteTools/Service/PlainPasteModule+Command.swift
import Foundation

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature?
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

@MainActor final class PlainPasteModule {
    var pastes = 0
    func paste() { pastes += 1 }
}

@MainActor enum NotchcastCore {
    static let pastePlain: PlainPasteModule? = PlainPasteModule()
}

enum NotchcastFeature { case pastePlain }

@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled = false
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled }
}

@main @MainActor struct PlainPasteCommandTest {
    static func main() {
        let command = PlainPasteModule.launcherCommand
        precondition(command.slug == "paste-plain-text")
        precondition(!command.isEnabled())
        NotchcastPreferences.shared.enabled = true
        precondition(command.isEnabled())
        command.run()
        precondition(NotchcastCore.pastePlain?.pastes == 1)
        print("PASS: plain-paste command availability and dispatch; fake paste target only")
    }
}
