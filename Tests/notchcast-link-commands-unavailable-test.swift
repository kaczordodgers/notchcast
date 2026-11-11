// notchcast-sources: Tinycast/Features/MachMBPFans/Model/*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/Service/RemoteFan*.swift
// notchcast-sources: Tinycast/Features/MachMBPFans/RemoteFanModule+Command.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/Model/*.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/Service/*.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/RemoteScreenModule+Command.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/Model/*.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/Service/BlockedDialogModule.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/BlockedDialogModule+Command.swift
// notchcast-sources: Tinycast/Features/MachLink/Model/MachLinkMessage.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-kit: command host
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
import Foundation

enum NotchcastFeature: Sendable {
    case machLink, machMBPFans, remoteScreen, island, islandStatusMessages, machBlockedDialogAlert
}
enum DialogTone {}

extension RemoteFanModule { static let shared: RemoteFanModule? = nil }
extension BlockedDialogModule { static let shared: BlockedDialogModule? = nil }
@MainActor final class RemoteScreenModule {
    static let shared: RemoteScreenModule? = nil
    let coordinator: RemoteScreenCoordinator
    init(coordinator: RemoteScreenCoordinator) { self.coordinator = coordinator }
}

@main struct LinkCommandsUnavailableTest {
    @MainActor static func main() async {
        var messages: [String] = []
        NotchcastHost.current.remoteResult = { messages.append($0) }
        BlockedDialogModule.checkCommand.run()
        precondition(messages == ["Could Not Check Other Mac Dialogs"], "\(messages)")
        RemoteFanModule.launcherCommand.run()
        while messages.count < 2 { await Task.yield() }
        precondition(messages.last == "Could not change fan mode.", "\(messages)")
        RemoteScreenModule.launcherCommand.run()
        while messages.count < 3 { await Task.yield() }
        precondition(messages.last == "Could not reach the other Mac.", "\(messages)")
        print("link commands: with no module registered each one reports its failure text")
    }
}
