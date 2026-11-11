// notchcast-sources: Tinycast/Features/PasteTools/PlainPasteModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/PasteTools/Service/PlainPasteModule+Command.swift
// notchcast-kit: command
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
import Foundation

@MainActor final class PlainPasteModule {
    var pastes = 0
    func paste() { pastes += 1 }
    var clipboard: ClipboardManager?
}

@MainActor final class ClipboardManager {}
@MainActor final class AppCore {
    static let shared = AppCore()
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

@main @MainActor struct PlainPasteCommandTest {
    static func main() {
        let command = PlainPasteModule.launcherCommand
        precondition(command.feature == .pastePlain, "The catalog switches the command off with this feature")
        command.run()
        precondition(PlainPasteModule.shared.pastes == 1, "The command reaches the module before registration")
        let entries = PlainPasteModule.register(AppCore.shared)
        precondition(entries.count == 1 && entries[0].requires == [.pastePlain] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === PlainPasteModule.shared)
        precondition(PlainPasteModule.shared.clipboard === AppCore.shared.clipboardManager)
        command.run()
        precondition(PlainPasteModule.shared.pastes == 2)
        print("PASS: plain-paste command dispatches to the one shared module; fake paste target only")
        print("PASS: registration builds the module from the core's clipboard behind its switch")
    }
}
