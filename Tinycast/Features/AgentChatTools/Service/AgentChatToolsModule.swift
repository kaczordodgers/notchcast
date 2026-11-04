import Foundation
import Observation

@MainActor
@Observable
final class AgentChatToolsModule: NotchcastModule {
    enum AddResult: Equatable { case added, binaryMissing, disabled }

    static let serverID = UUID(uuidString: "A691601E-F1F5-43A5-9961-A6815423BD50")!
    private let store: MCPSettingsStore
    private let binaryPath: String
    private let isBinaryInstalled: () -> Bool
    private let onChange: () -> Void
    private(set) var isRunning = false

    var isAdded: Bool { store.server(id: Self.serverID) != nil }

    init(
        store: MCPSettingsStore, binaryPath: String,
        isBinaryInstalled: @escaping () -> Bool, onChange: @escaping () -> Void = {}
    ) {
        self.store = store
        self.binaryPath = binaryPath
        self.isBinaryInstalled = isBinaryInstalled
        self.onChange = onChange
    }

    func start() {
        isRunning = true
        if isAdded, add() == .binaryMissing {
            stop()
            isRunning = true
        }
    }

    func stop() {
        isRunning = false
        guard var server = store.server(id: Self.serverID) else { return }
        server.isEnabled = false
        store.save(server)
        onChange()
    }

    @discardableResult
    func add() -> AddResult {
        guard isRunning else { return .disabled }
        guard isBinaryInstalled() else { return .binaryMissing }
        let trust = store.server(id: Self.serverID)?.trust ?? .ask
        store.save(MCPServer(
            id: Self.serverID, name: "Notchcast", slug: "notchcast",
            transport: .stdio(command: binaryPath, arguments: ["mcp"], environmentKeys: []),
            trust: trust))
        onChange()
        return .added
    }

    func remove() {
        store.remove(id: Self.serverID)
        onChange()
    }
}
