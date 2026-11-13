// notchcast-sources: Tinycast/Features/Shelf/Model/*.swift
// notchcast-sources: Tinycast/Features/Shelf/Service/ShelfReceivedStore.swift
// notchcast-sources: Tinycast/Features/Shelf/Service/ShelfLinkStatus.swift
// notchcast-sources: Tinycast/Features/Shelf/ShelfModule*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-kit: host command
// notchcast-sources: Tests/Support/NotchcastPreferencesFake.swift
// notchcast-sources: Tinycast/Platform/PasteboardFiles.swift
import AppKit

enum NotchcastFeature: Sendable { case shelfBetweenMacs, machLink }
enum DialogTone {}

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
        let entries = ShelfModule.register()
        precondition(entries.count == 1 && entries[0].module === module)
        precondition(entries[0].requires == [.shelfBetweenMacs] && entries[0].requiresAny.isEmpty)
        let peer = ShelfPeer()
        module.transport = peer
        module.linkStatus = peer
        module.start()
        ShelfModule.showCommand.run()
        precondition(SettingsActionCommands.openedShelf)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Test shelf text", forType: .string)
        let command = ShelfModule.clipboardCommand { board }
        precondition(command.feature == .shelfBetweenMacs)
        command.run()
        while Probe.messages.isEmpty { await Task.yield() }
        precondition(peer.items.count == 1)
        precondition(peer.items[0].data == Data("Test shelf text".utf8))
        precondition(Probe.messages.last == "Sent Clipboard to Other Mac")
        board.clearContents()
        board.writeObjects([NSURL(string: "https://example.com/shelf")!])
        command.run()
        while Probe.messages.count < 2 { await Task.yield() }
        precondition(peer.items.last?.kind == .link)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try! Data("file payload".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        PasteboardFiles.write(file, to: board)
        command.run()
        while Probe.messages.count < 3 { await Task.yield() }
        precondition(peer.items.last?.kind == .file && peer.items.last?.data == Data("file payload".utf8))
        peer.shelfPeerAvailable = false
        command.run()
        while Probe.messages.count < 4 { await Task.yield() }
        precondition(peer.items.count == 3)
        precondition(Probe.messages.last == "Could Not Send Clipboard to Other Mac")
        board.clearContents()
        command.run()
        precondition(Probe.messages.count == 5)
        module.stop()
        print("shelf command: fake peer received text; unavailable peer, empty clipboard and gate passed")
    }
}
