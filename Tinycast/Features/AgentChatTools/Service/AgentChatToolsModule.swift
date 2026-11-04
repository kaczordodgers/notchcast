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
    private let defaults: UserDefaults
    private static let disabledKey = "notchcast.agentChatTools.disabledServer"
    private(set) var isRunning = false

    var isAdded: Bool { store.server(id: Self.serverID) != nil }

    init(
        store: MCPSettingsStore, binaryPath: String,
        isBinaryInstalled: @escaping () -> Bool, onChange: @escaping () -> Void = {},
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.binaryPath = binaryPath
        self.isBinaryInstalled = isBinaryInstalled
        self.onChange = onChange
        self.defaults = defaults
    }

    func start() {
        isRunning = true
        guard var server = store.server(id: Self.serverID) else { return }
        if !isBinaryInstalled() {
            stop()
            isRunning = true
        } else if defaults.bool(forKey: Self.disabledKey) {
            server.isEnabled = true
            store.save(server)
            defaults.removeObject(forKey: Self.disabledKey)
            onChange()
        }
    }

    func stop() {
        isRunning = false
        guard var server = store.server(id: Self.serverID), server.isEnabled else { return }
        defaults.set(true, forKey: Self.disabledKey)
        server.isEnabled = false
        store.save(server)
        onChange()
    }

    @discardableResult
    func add() -> AddResult {
        guard isRunning else { return .disabled }
        guard isBinaryInstalled() else { return .binaryMissing }
        guard !isAdded else { return .added }
        store.save(MCPServer(
            id: Self.serverID, name: "Notchcast", slug: "notchcast",
            transport: .stdio(command: binaryPath, arguments: ["mcp"], environmentKeys: []),
            trust: .ask))
        onChange()
        return .added
    }

    func remove() {
        defaults.removeObject(forKey: Self.disabledKey)
        store.remove(id: Self.serverID)
        onChange()
    }
}
