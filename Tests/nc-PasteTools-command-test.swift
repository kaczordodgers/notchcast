// notchcast-sources: Tinycast/Features/PasteTools/PlainPasteModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
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
    var clipboard: ClipboardManager?
}

@MainActor final class ClipboardManager {}
@MainActor final class AppCore {
    let clipboardManager = ClipboardManager()
}
extension PlainPasteModule: NotchcastModule {
    convenience init(clipboard: ClipboardManager) {
        self.init()
        self.clipboard = clipboard
    }
    func start() {}
    func stop() {}
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
        precondition(!command.isEnabled())
        NotchcastPreferences.shared.enabled = true
        precondition(command.isEnabled())
        precondition(PlainPasteModule.shared == nil)
        command.run()
        let core = AppCore()
        let entries = PlainPasteModule.register(core)
        precondition(entries.count == 1 && entries[0].requires == [.pastePlain] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === PlainPasteModule.shared)
        precondition(PlainPasteModule.shared?.clipboard === core.clipboardManager)
        command.run()
        precondition(PlainPasteModule.shared?.pastes == 1)
        print("PASS: plain-paste command availability and dispatch; fake paste target only")
        print("PASS: registration builds the module from the core's clipboard behind its switch")
    }
}
