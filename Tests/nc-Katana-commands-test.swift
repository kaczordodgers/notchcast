// notchcast-sources: Tinycast/Features/Katana/Model/*.swift Tinycast/Features/Katana/Service/*.swift
// notchcast-sources: Tinycast/Features/Katana/KatanaModule*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift Tinycast/Features/AgentBridge/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
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
@MainActor enum NotchcastCore {
    static let midi = CommandMIDI()
    static let katana = KatanaModule(midi: midi)
}
@MainActor final class AppCore {
    enum Tone { case danger, neutral }
    static let shared = AppCore()
    var messages: [(String, Tone)] = []
    func showMessage(_ text: String, tone: Tone) { messages.append((text, tone)) }
}
@MainActor final class CommandMIDI: KatanaMIDILayer {
    var endpoints = ["KATANA Test"]
    var changed: (() -> Void)?
    var received: (([UInt8]) -> Void)?
    var packets: [KatanaSysEx.Message] = []
    var channel: UInt8 = 0
    var fail = false
    func start() throws {}
    func stop() {}
    func connect(_ name: String) throws {}
    func send(_ bytes: [UInt8]) throws {
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
        let midi = NotchcastCore.midi
        let module = NotchcastCore.katana
        module.start()
        defer { module.stop() }
        for (command, channel) in zip(commands, KatanaChannel.allCases) {
            AppCore.shared.messages = []
            midi.packets = []
            command.run()
            while AppCore.shared.messages.isEmpty { await Task.yield() }
            precondition(midi.packets.contains { $0.address == KatanaSysEx.selectChannel && $0.data == [0, channel.rawValue] })
            precondition(module.client.channel == channel)
            precondition(AppCore.shared.messages[0].1 == .neutral)
            precondition(AppCore.shared.messages[0].0.contains(channel.title))
            print("PASS: \(command.name) selects \(channel.rawValue) and reports success")
        }
        midi.endpoints = []
        midi.changed?()
        for command in commands {
            midi.packets = []
            AppCore.shared.messages = []
            command.run()
            while AppCore.shared.messages.isEmpty { await Task.yield() }
            precondition(midi.packets.isEmpty)
            precondition(AppCore.shared.messages[0].0 == KatanaError.unavailable.localizedDescription)
            precondition(AppCore.shared.messages[0].1 == .danger)
        }
        print("PASS: all disconnected commands report danger and send nothing")
        midi.endpoints = ["KATANA Test"]
        midi.changed?()
        midi.fail = true
        AppCore.shared.messages = []
        commands[0].run()
        while AppCore.shared.messages.isEmpty { await Task.yield() }
        precondition(AppCore.shared.messages[0].1 == .danger)
        precondition(AppCore.shared.messages[0].0 == KatanaError.verificationFailed.localizedDescription)
        print("PASS: transport failure reports existing KatanaError with danger")
        NotchcastPreferences.shared.enabled = false
        precondition(commands.filter { $0.isEnabled() }.isEmpty)
        print("PASS: switch off removes all five commands")
        let path = "Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog+All.swift"
        let catalog = try String(contentsOfFile: path, encoding: .utf8)
        for name in ["panel", "a1", "a2", "b1", "b2"] {
            precondition(catalog.contains("        KatanaModule.\(name)Command,"))
        }
        print("PASS: production catalog includes all five commands")
    }
}
