// notchcast-sources: Tinycast/Features/Katana/Model/*.swift Tinycast/Features/Katana/Service/*.swift
// notchcast-sources: Tinycast/Features/Katana/KatanaModule.swift Tinycast/Features/Katana/KatanaModule+Commands.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift Tinycast/Features/AgentBridge/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
import Foundation

enum NotchcastFeature: Sendable { case katana }
enum SettingsTab: Sendable { case notchcast }
struct AppEntry {
    enum Kind { case command }
    let id: String
    let name: String
    let url: URL
    let bundleID: String?
    let kind: Kind
    let settingsOwner: SettingsTab?
    let symbolName: String
}
@MainActor final class NotchcastPreferences {
    static let shared = NotchcastPreferences()
    var enabled = true
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled }
}
extension KatanaModule {
    static let midi = CommandMIDI()
    static let shared = KatanaModule(midi: midi)
}
enum DialogTone: Sendable {
    case neutral
    case success
    case danger
}
@MainActor final class CommandMIDI: KatanaMIDILayer {
    var endpoints = ["KATANA Test"]
    var changed: (() -> Void)?
    var received: (([UInt8]) -> Void)?
    var packets: [KatanaSysEx.Message] = []
    var channel: UInt8 = 0
    var fail = false
    var cancel = false
    var disable = false
    func start() throws {}
    func stop() {}
    func connect(_ name: String) throws {}
    func send(_ bytes: [UInt8]) throws {
        if cancel { throw CancellationError() }
        if disable { NotchcastPreferences.shared.enabled = false }
        if fail { throw KatanaError.verificationFailed }
        let message = try KatanaSysEx.decode(bytes)
        packets.append(message)
        if message.address == KatanaSysEx.selectChannel { channel = message.data[1] }
        if message.command == 0x11 {
            received?(try KatanaSysEx.write(message.address,
                message.address == KatanaSysEx.activeChannel ? [0, channel] : Array("CLEAN           ".utf8)))
        }
    }
}
@main @MainActor struct KatanaCommandsTest {
    static func main() async throws {
        let commands = [KatanaModule.panelCommand, KatanaModule.a1Command, KatanaModule.a2Command,
                        KatanaModule.b1Command, KatanaModule.b2Command]
        var messages: [(String, DialogTone)] = []
        NotchcastHost.current.showMessage = { messages.append(($0, $1)) }
        let midi = KatanaModule.midi
        let module = KatanaModule.shared
        module.start()
        defer { module.stop() }
        for (command, channel) in zip(commands, KatanaChannel.allCases) {
            messages = []
            midi.packets = []
            command.run()
            while messages.isEmpty { await Task.yield() }
            precondition(midi.packets.contains { $0.address == KatanaSysEx.selectChannel && $0.data == [0, channel.rawValue] })
            precondition(module.client.channel == channel)
            precondition(messages[0].1 == .success)
            precondition(command.name == "Select Katana \(channel.title)")
            precondition(messages[0].0 == "Katana \(channel.title) Selected")
            print("PASS: \(command.name) selects \(channel.rawValue) and reports success")
        }
        midi.endpoints = []
        midi.changed?()
        for command in commands {
            midi.packets = []
            messages = []
            command.run()
            while messages.isEmpty { await Task.yield() }
            precondition(midi.packets.isEmpty)
            precondition(messages[0].0 == KatanaError.unavailable.localizedDescription)
            precondition(messages[0].1 == .danger)
        }
        print("PASS: all disconnected commands report danger and send nothing")
        midi.endpoints = ["KATANA Test"]
        midi.changed?()
        midi.fail = true
        messages = []
        commands[0].run()
        while messages.isEmpty { await Task.yield() }
        precondition(messages[0].1 == .danger)
        precondition(messages[0].0 == KatanaError.verificationFailed.localizedDescription)
        print("PASS: transport failure reports existing KatanaError with danger")
        midi.fail = false
        midi.cancel = true
        var reports = 0
        await module.selectChannel(.a1) { _, _ in reports += 1 }
        precondition(reports == 0)
        midi.cancel = false
        midi.disable = true
        await module.selectChannel(.a1) { _, _ in reports += 1 }
        precondition(reports == 0)
        midi.fail = true
        await module.selectChannel(.a1) { _, _ in reports += 1 }
        precondition(reports == 0)
        print("PASS: cancellation and switch-off suppress success and danger reports")
        NotchcastPreferences.shared.enabled = false
        precondition(commands.filter { $0.isEnabled() }.isEmpty)
        print("PASS: switch off removes all five commands")
    }
}
