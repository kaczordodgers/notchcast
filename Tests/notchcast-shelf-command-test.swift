// notchcast-sources: Tinycast/Features/Shelf/Model/*.swift
// notchcast-sources: Tinycast/Features/Shelf/Service/ShelfReceivedStore.swift
// notchcast-sources: Tinycast/Features/Shelf/Service/ShelfLinkStatus.swift
// notchcast-sources: Tinycast/Features/Shelf/ShelfModule*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation

enum NotchcastFeature: Sendable { case shelfBetweenMacs, machLink }

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
    static let shelf = ShelfModule()
    static var messages: [String] = []
    static func remoteResult(_ text: String) { messages.append(text) }
}

@MainActor final class ShelfPeer: ShelfLinkStatus, ShelfTransport {
    var shelfPeerAvailable = true
    var items: [ShelfItem] = []
    func sendShelfItem(_ item: ShelfItem) async throws { items.append(item) }
}

@main struct ShelfCommandTest {
    @MainActor static func main() async {
        let module = NotchcastCore.shelf
        let peer = ShelfPeer()
        module.transport = peer
        module.linkStatus = peer
        module.start()
        let command = ShelfModule.clipboardCommand { "Test shelf text" }
        precondition(command.feature == .shelfBetweenMacs && command.isEnabled())
        NotchcastPreferences.shared.enabled = false
        precondition(!command.isEnabled())
        command.run()
        while NotchcastCore.messages.isEmpty { await Task.yield() }
        precondition(peer.items.count == 1)
        precondition(peer.items[0].data == Data("Test shelf text".utf8))
        precondition(NotchcastCore.messages.last == "Sent Clipboard to Other Mac")
        peer.shelfPeerAvailable = false
        ShelfModule.clipboardCommand { "Another item" }.run()
        while NotchcastCore.messages.count < 2 { await Task.yield() }
        precondition(peer.items.count == 1)
        precondition(NotchcastCore.messages.last == "Could Not Send Clipboard to Other Mac")
        ShelfModule.clipboardCommand { nil }.run()
        precondition(NotchcastCore.messages.count == 3)
        module.stop()
        print("shelf command: fake peer received text; unavailable peer, empty clipboard and gate passed")
    }
}
