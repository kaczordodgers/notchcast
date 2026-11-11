// notchcast-sources: Tinycast/Features/MachBlockedDialog/Model/*.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/Service/BlockedDialogModule.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/BlockedDialogModule+Command.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-kit: command
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
import Foundation

enum NotchcastFeature: Sendable {
    case machLink, island, islandStatusMessages, machBlockedDialogAlert
}
enum DialogTone {}

@MainActor enum Probe {
    static var requests = 0
    static var messages: [String] = []
    static var fail = false
    static var windows: [BlockedDialogWindow] = []
}

extension BlockedDialogModule {
    static let shared: BlockedDialogModule? = BlockedDialogModule(transport: { request in
        Probe.requests += 1
        if Probe.fail { throw MachLinkMessage.Failure.disconnected }
        return try MachLinkMessage(id: request.id, method: request.method,
                                  value: Probe.windows)
    }, enabled: { true }, present: { _ in })
}

@main struct BlockedDialogCommandTest {
    @MainActor static func main() async {
        let command = BlockedDialogModule.checkCommand
        precondition(command.feature == .machBlockedDialogAlert)
        NotchcastHost.current.remoteResult = { Probe.messages.append($0) }
        BlockedDialogModule.shared?.start()
        command.run()
        while Probe.messages.isEmpty { await Task.yield() }
        precondition(Probe.requests == 1)
        precondition(Probe.messages == ["Other Mac Dialog Check Complete"])
        Probe.fail = true
        command.run()
        while Probe.messages.count < 2 { await Task.yield() }
        precondition(Probe.requests == 2)
        precondition(Probe.messages.last == "Could Not Check Other Mac Dialogs")
        Probe.fail = false
        Probe.windows = [.init(owner: "SecurityAgent", processID: 42, windowID: 9,
            layer: 1, width: 300, height: 100)]
        command.run()
        while Probe.messages.count < 3 { await Task.yield() }
        precondition(Probe.messages.last == "Other Mac: SecurityAgent is waiting.")
        BlockedDialogModule.shared?.stop()
        print("blocked dialog command: fake transport reached; success, failure and gate passed")
    }
}
