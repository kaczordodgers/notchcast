// notchcast-sources: Tinycast/Features/Katana/Model/*.swift Tinycast/Features/Katana/Service/*.swift
// notchcast-sources: Tinycast/Features/Katana/KatanaModule*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift Tinycast/Features/AgentBridge/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommand.swift
// notchcast-reads: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog+All.swift
// notchcast-reads: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettingsModule+Groups.swift
// notchcast-reads: Tinycast/Features/Katana/KatanaDescriptor.swift
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
enum DialogTone: Sendable {
    case neutral
    case success
    case danger
}
@MainActor final class AppCore {
    static let shared = AppCore()
    var messages: [(String, DialogTone)] = []
    func showMessage(_ message: String, tone: DialogTone = .success) { messages.append((message, tone)) }
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
            precondition(AppCore.shared.messages[0].1 == .success)
            precondition(command.name == "Select Katana \(channel.title)")
            precondition(command.slug == "katana-\(channel.title.lowercased())")
            precondition(AppCore.shared.messages[0].0 == "Katana \(channel.title) Selected")
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
        let path = "Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog+All.swift"
        let catalog = try String(contentsOfFile: path, encoding: .utf8)
        for name in ["panel", "a1", "a2", "b1", "b2"] {
            precondition(catalog.contains("        KatanaModule.\(name)Command,"))
        }
        print("PASS: production catalog includes all five commands")
        let settings = try String(contentsOfFile:
            "Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettingsModule+Groups.swift", encoding: .utf8)
        precondition(settings.components(separatedBy: ".feature(.katana,").count == 2)
        let feature = try String(contentsOfFile:
            "Tinycast/Features/Katana/KatanaDescriptor.swift", encoding: .utf8)
        precondition(feature.contains("group: .system,"))
        print("PASS: Katana is listed once in Settings")
    }
}
