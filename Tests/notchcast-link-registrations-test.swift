// notchcast-sources: Tinycast/Features/MachMBPFans/RemoteFanModule+Registration.swift
// notchcast-sources: Tinycast/Features/RemoteScreen/RemoteScreenModule+Registration.swift
// notchcast-sources: Tinycast/Features/MachBlockedDialog/BlockedDialogModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
import Foundation

enum NotchcastFeature {
    case machMBPFans, remoteScreen, machBlockedDialogAlert
}
@MainActor final class NotchcastPreferences {
    func isOn(_ feature: NotchcastFeature) -> Bool { true }
}
@MainActor final class AppCore {}
@MainActor final class MachLinkChannel {}

@MainActor struct MachLinkFanTransport { let channel: MachLinkChannel }
@MainActor final class RemoteFanModule: NotchcastModule {
    static var linkChannel: MachLinkChannel?
    let transport: MachLinkFanTransport
    init(transport: MachLinkFanTransport) { self.transport = transport }
    func start() {}
    func stop() {}
}
@MainActor final class RemoteScreenModule: NotchcastModule {
    static var linkChannel: MachLinkChannel?
    let channel: MachLinkChannel
    init(channel: MachLinkChannel) { self.channel = channel }
    func start() {}
    func stop() {}
}
@MainActor final class BlockedDialogModule: NotchcastModule {
    static var linkChannel: MachLinkChannel?
    let channel: MachLinkChannel
    init(channel: MachLinkChannel) { self.channel = channel }
    static func linked(to channel: MachLinkChannel) -> BlockedDialogModule { BlockedDialogModule(channel: channel) }
    func start() {}
    func stop() {}
}

@main struct LinkRegistrationsTest {
    @MainActor static func main() {
        let core = AppCore()
        precondition(RemoteFanModule.register(core).isEmpty && RemoteFanModule.shared == nil)
        precondition(RemoteScreenModule.register(core).isEmpty && RemoteScreenModule.shared == nil)
        precondition(BlockedDialogModule.register(core).isEmpty && BlockedDialogModule.shared == nil)

        let channel = MachLinkChannel()
        RemoteFanModule.linkChannel = channel
        RemoteScreenModule.linkChannel = channel
        BlockedDialogModule.linkChannel = channel

        let fans = RemoteFanModule.register(core)
        precondition(fans.count == 1 && fans[0].module === RemoteFanModule.shared)
        precondition(fans[0].requires == [.machMBPFans] && fans[0].requiresAny.isEmpty)
        precondition(RemoteFanModule.shared?.transport.channel === channel)

        let screen = RemoteScreenModule.register(core)
        precondition(screen.count == 1 && screen[0].module === RemoteScreenModule.shared)
        precondition(screen[0].requires == [.remoteScreen] && screen[0].requiresAny.isEmpty)
        precondition(RemoteScreenModule.shared?.channel === channel)

        let dialogs = BlockedDialogModule.register(core)
        precondition(dialogs.count == 1 && dialogs[0].module === BlockedDialogModule.shared)
        precondition(dialogs[0].requires == [.machBlockedDialogAlert])
        precondition(dialogs[0].requiresAny.isEmpty && BlockedDialogModule.shared?.channel === channel)
        print("link registrations: no entry before the hub hands the channel; then one entry each on that channel")
    }
}
