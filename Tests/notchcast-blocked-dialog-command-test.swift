// notchcast-sources: Tinycast/Features/MachBlockedDialog/Model/*.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/Service/BlockedDialogModule.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/BlockedDialogModule+Command.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation

enum NotchcastFeature: Sendable {
    case machLink, island, islandStatusMessages, machBlockedDialogAlert
}

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature?
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled = true
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled }
}

@MainActor enum NotchcastCore {
    static var requests = 0
    static var messages: [String] = []
    static var fail = false
    static var windows: [BlockedDialogWindow] = []
    static let blockedDialogs = BlockedDialogModule(transport: { request in
        requests += 1
        if fail { throw MachLinkMessage.Failure.disconnected }
        return try MachLinkMessage(id: request.id, method: request.method,
                                  value: windows)
    }, enabled: { true }, present: { _ in })
    static func remoteResult(_ text: String) { messages.append(text) }
}

@main struct BlockedDialogCommandTest {
    @MainActor static func main() async {
        let command = BlockedDialogModule.checkCommand
        precondition(command.feature == .machBlockedDialogAlert)
        precondition(command.isEnabled())
        NotchcastPreferences.shared.enabled = false
        precondition(!command.isEnabled())
        NotchcastCore.blockedDialogs.start()
        command.run()
        while NotchcastCore.messages.isEmpty { await Task.yield() }
        precondition(NotchcastCore.requests == 1)
        precondition(NotchcastCore.messages == ["Other Mac Dialog Check Complete"])
        NotchcastCore.fail = true
        command.run()
        while NotchcastCore.messages.count < 2 { await Task.yield() }
        precondition(NotchcastCore.requests == 2)
        precondition(NotchcastCore.messages.last == "Could Not Check Other Mac Dialogs")
        NotchcastCore.fail = false
        NotchcastCore.windows = [.init(owner: "SecurityAgent", processID: 42, windowID: 9,
            layer: 1, width: 300, height: 100)]
        command.run()
        while NotchcastCore.messages.count < 3 { await Task.yield() }
        precondition(NotchcastCore.messages.last == "Other Mac: SecurityAgent is waiting.")
        NotchcastCore.blockedDialogs.stop()
        print("blocked dialog command: fake transport reached; success, failure and gate passed")
    }
}
