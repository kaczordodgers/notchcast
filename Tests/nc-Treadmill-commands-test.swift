// notchcast-sources: Tinycast/Features/Treadmill/Model/*.swift
// notchcast-sources: Tinycast/Features/Treadmill/Service/*.swift
// notchcast-sources: Tinycast/Features/Treadmill/TreadmillCommands.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Service/*.swift
// notchcast-kit: core host command
import Foundation

enum DialogTone: Sendable { case neutral, success, danger }
extension TreadmillCoordinator { static var shared: TreadmillCoordinator! }
@MainActor private final class FakeTransport: TreadmillTransport {
    var maintainsConnection = true
    var onReady: (() -> Void)?
    var onFailure: (((any Error)?) -> Void)?
    var onBytes: ((Data) -> Void)?
    var onDisconnect: (() -> Void)?
    var sent: [Data] = []
    var fail = false
    func open() {}
    func close() {}
    func send(_ data: Data) throws {
        if fail { throw TreadmillFailure.unavailable }
        sent.append(data)
    }
    func status(_ phase: UInt8, speed: UInt8 = 40) {
        onBytes?(TreadmillProtocol.frame([0x51, phase, speed, 0, 60, 0, 10, 0, 0, 0, 90, 0, 0, 0, 0, 0]))
    }
}
@main @MainActor struct CommandsTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let domain = "nc-treadmill-commands-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        let transport = FakeTransport()
        let coordinator = TreadmillCoordinator(transport: transport,
            history: TreadmillHistoryStore(repository: TreadmillRepository(directory: root)),
            preferences: TreadmillPreferences(defaults: defaults))
        TreadmillCoordinator.shared = coordinator
        var messages: [(String, DialogTone)] = []
        NotchcastHost.current.showMessage = { messages.append(($0, $1)) }
        try await coordinator.prepare()
        coordinator.setEnabled(.walk, true)
        let all = [TreadmillCommands.start, TreadmillCommands.stop, TreadmillCommands.pause,
                   TreadmillCommands.faster, TreadmillCommands.slower]
        for command in all {
            command.run()
            precondition(messages.last?.1 == .danger && transport.sent.isEmpty)
            precondition(messages.last?.0 == "The walking pad is not connected.")
        }
        print("Treadmill commands: all five disconnected actions report danger without writes")
        transport.onFailure?(TreadmillBluetoothFailure.unauthorized)
        precondition(coordinator.lastError as? TreadmillBluetoothFailure == .unauthorized)
        TreadmillCommands.start.run()
        precondition(messages.last?.0 == "The walking pad is not connected.")
        precondition(TreadmillBluetoothFailure.unauthorized.localizedDescription
            == "Allow Bluetooth access in System Settings.")
        print("Treadmill commands: exact error messages and stale connection error regression passed")
        transport.onReady?()
        transport.sent = []
        TreadmillCommands.pause.run()
        precondition(messages.last?.0 == "There is no walk in progress.")
        TreadmillCommands.start.run()
        let startFrame = try TreadmillProtocol.start(minutes: 0)
        precondition(transport.sent == [startFrame])
        precondition(coordinator.engine.requestedSpeed == 4)
        precondition(messages.last?.0 == "Walk start requested at \(coordinator.engine.requestedSpeed!.formatted()) km/h.")
        TreadmillCommands.start.run()
        precondition(messages.last?.0 == "A walk is already in progress.")
        messages.removeLast()
        transport.status(3)
        TreadmillCommands.faster.run()
        let fasterFrame = try TreadmillProtocol.speed(4.5)
        precondition(transport.sent.last == fasterFrame)
        TreadmillCommands.slower.run()
        let slowerFrame = try TreadmillProtocol.speed(4)
        precondition(transport.sent.last == slowerFrame)
        TreadmillCommands.pause.run()
        precondition(transport.sent.last == TreadmillProtocol.pause)
        transport.status(10, speed: 0)
        TreadmillCommands.pause.run()
        precondition(transport.sent.last == TreadmillProtocol.resume)
        TreadmillCommands.stop.run()
        precondition(transport.sent.last == TreadmillProtocol.stop)
        precondition(messages.suffix(6).allSatisfy { $0.1 == .success })
        let count = transport.sent.count
        transport.fail = true
        TreadmillCommands.stop.run()
        precondition(transport.sent.count == count && messages.last?.1 == .danger)
        print("Treadmill commands: start defaults, stop, pause/resume, faster/slower frames and thrown-error feedback passed")
        let preferences = NotchcastPreferences.shared
        let previous = preferences.isOn(.treadmillWalk)
        defer { preferences.set(.treadmillWalk, previous) }
        preferences.set(.treadmillWalk, false)
        precondition(all.filter { $0.isEnabled() }.isEmpty)
        preferences.set(.treadmillWalk, true)
        precondition(all.allSatisfy { $0.isEnabled() })
        print("Treadmill commands: switch off excludes all five commands; switch on enables all five")
        transport.fail = false
        await coordinator.stopForTermination()
    }
}
