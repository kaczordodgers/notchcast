// notchcast-sources: Tinycast/Features/Katana/Model/*.swift Tinycast/Features/Katana/Service/*.swift
// notchcast-sources: Tinycast/Features/Katana/KatanaModule.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift Tinycast/Features/AgentBridge/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
import Foundation

@MainActor
final class FakeMIDILayer: KatanaMIDILayer {
    var endpoints = ["Other MIDI"]
    var changed: (() -> Void)?
    var received: (([UInt8]) -> Void)?
    var packets: [[UInt8]] = []
    var connected: String?
    var reply = true
    func start() throws {}
    func stop() { connected = nil }
    func connect(_ name: String) throws { connected = name }
    func send(_ bytes: [UInt8]) throws {
        packets.append(bytes)
        let request = try KatanaSysEx.decode(bytes)
        if request.command == 0x11, reply {
            let response = try KatanaSysEx.write(request.address, [0, 5])
            received?(Array(response.prefix(7)))
            received?(Array(response.dropFirst(7)))
        }
    }
}

@main
@MainActor
struct KatanaTransportTests {
    static func main() async throws {
        let midi = FakeMIDILayer()
        let transport = KatanaMIDITransport(midi: midi)
        transport.start()
        precondition(transport.connectionID == nil)
        do {
            try await transport.send(KatanaSysEx.write(KatanaSysEx.selectChannel, [0, 5]))
            fatalError("Absent amp accepted send")
        } catch { precondition(error as? KatanaError == .unavailable) }
        precondition(midi.packets.isEmpty)
        midi.endpoints.append("KATANA Gen 3 Bluetooth")
        midi.changed?()
        let connection = transport.connectionID
        precondition(connection != nil && midi.connected == "KATANA Gen 3 Bluetooth")
        try await transport.send(KatanaSysEx.write(KatanaSysEx.selectChannel, [0, 5]))
        precondition(midi.packets.last == [0xF0, 0x41, 0x10, 1, 5, 7, 0x12, 0x7F, 0, 1, 0, 0, 5, 0x7B, 0xF7])
        let reply = try await transport.exchange(KatanaSysEx.read(0, count: 2))
        let decoded = try KatanaSysEx.decode(reply)
        precondition(decoded.data == [0, 5])
        midi.endpoints = []
        midi.changed?()
        precondition(transport.connectionID == nil)
        midi.endpoints = ["KATANA USB"]
        midi.changed?()
        precondition(transport.connectionID != nil && transport.connectionID != connection)
        transport.stop()
        let module = KatanaModule(midi: midi)
        let index = AgentActionIndex()
        module.configure(index: index)
        precondition(index.actionIDs.isEmpty)
        module.start()
        precondition(index.actionIDs == ["device.katana.channel", "device.katana.tone"])
        precondition(index.stateIDs == ["device.katana"])
        module.stop()
        precondition(index.actionIDs.isEmpty && index.stateIDs.isEmpty)
        module.start()
        precondition(index.actionIDs.count == 2)
        module.stop()
        print("Katana transport: absent/found, exact bytes, reply, reconnect, registration on/off passed; fake MIDI only")
    }
}
