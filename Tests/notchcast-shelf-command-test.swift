// notchcast-sources: Tinycast/Features/Shelf/Model/*.swift
// notchcast-sources: Tinycast/Features/Shelf/Service/ShelfReceivedStore.swift
// notchcast-sources: Tinycast/Features/Shelf/Service/ShelfLinkStatus.swift
// notchcast-sources: Tinycast/Features/Shelf/ShelfModule*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-kit: command
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
import Foundation

enum NotchcastFeature: Sendable { case shelfBetweenMacs, machLink }
enum DialogTone {}
@MainActor final class AppCore {}

@MainActor enum SettingsActionCommands {
    static var openedShelf = false
    static func show(_ tab: SettingsTab, _ feature: NotchcastFeature) {
        openedShelf = feature == .shelfBetweenMacs
    }
}

@MainActor enum Probe {
    static var messages: [String] = []
}

@MainActor final class ShelfPeer: ShelfLinkStatus, ShelfTransport {
    var shelfPeerAvailable = true
    var items: [ShelfItem] = []
    func sendShelfItem(_ item: ShelfItem) async throws { items.append(item) }
}

@main struct ShelfCommandTest {
    @MainActor static func main() async {
        NotchcastHost.current.remoteResult = { Probe.messages.append($0) }
        let module = ShelfModule.shared
        let entries = ShelfModule.register(AppCore())
        precondition(entries.count == 1 && entries[0].module === module)
        precondition(entries[0].requires == [.machLink, .shelfBetweenMacs] && entries[0].requiresAny.isEmpty)
        let peer = ShelfPeer()
        module.transport = peer
        module.linkStatus = peer
        module.start()
        ShelfModule.showCommand.run()
        precondition(SettingsActionCommands.openedShelf)
        let command = ShelfModule.clipboardCommand { "Test shelf text" }
        precondition(command.feature == .shelfBetweenMacs && command.isEnabled())
        NotchcastPreferences.shared.enabled = false
        precondition(!command.isEnabled())
        command.run()
        while Probe.messages.isEmpty { await Task.yield() }
        precondition(peer.items.count == 1)
        precondition(peer.items[0].data == Data("Test shelf text".utf8))
        precondition(Probe.messages.last == "Sent Clipboard to Other Mac")
        peer.shelfPeerAvailable = false
        ShelfModule.clipboardCommand { "Another item" }.run()
        while Probe.messages.count < 2 { await Task.yield() }
        precondition(peer.items.count == 1)
        precondition(Probe.messages.last == "Could Not Send Clipboard to Other Mac")
        ShelfModule.clipboardCommand { nil }.run()
        precondition(Probe.messages.count == 3)
        module.stop()
        print("shelf command: fake peer received text; unavailable peer, empty clipboard and gate passed")
    }
}
