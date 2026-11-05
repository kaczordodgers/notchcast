// notchcast-sources: Tinycast/Features/Katana/Model/*.swift Tinycast/Features/Katana/Service/*.swift
// notchcast-sources: Tinycast/Features/Katana/KatanaModule.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift Tinycast/Features/AgentBridge/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
import Foundation
import CoreMIDI

@MainActor
final class FakeMIDILayer: KatanaMIDILayer {
    var endpoints = ["KATANA fake"]
    var changed: (() -> Void)?
    var received: (([UInt8]) -> Void)?
    var packets: [[UInt8]] = []
    var connected: String?
    func start() throws {}
    func stop() {}
    func connect(_ name: String) throws { connected = name }
    func send(_ bytes: [UInt8]) throws { packets.append(bytes) }
}

@main @MainActor
struct KatanaTransportTests {
    static func main() async throws {
        try await virtualMIDI()
        let picker = FakeMIDILayer()
        picker.endpoints = ["Other MIDI"]
        let picking = KatanaMIDITransport(midi: picker)
        picking.start()
        precondition(picking.connectionID == nil && picker.connected == nil)
        do {
            try await picking.send(KatanaSysEx.write(0, [0, 5]))
            fatalError("Absent amp accepted send")
        } catch { precondition(error as? KatanaError == .unavailable) }
        precondition(picker.packets.isEmpty, "Disconnected send writes nothing")
        for name in ["KATANA", "Boss Katana", "katana Gen 3 Bluetooth", "BoSs kAtAnA USB"] {
            picker.endpoints = ["Other MIDI", name]
            picker.changed?()
            precondition(picking.connectionID != nil && picker.connected == name)
        }
        picking.stop()
        print("PASS: case-insensitive endpoint picking; absent amp refuses send with zero writes")
        let module = KatanaModule(midi: picker)
        let index = AgentActionIndex()
        module.configure(index: index)
        precondition(index.actionIDs.isEmpty && index.stateIDs.isEmpty)
        for _ in 0..<2 {
            module.start()
            precondition(index.actionIDs == ["device.katana.channel", "device.katana.tone"])
            precondition(index.stateIDs == ["device.katana"])
            module.stop()
            precondition(index.actionIDs.isEmpty && index.stateIDs.isEmpty)
        }
        print("PASS: module start registers agent actions and state; stop removes them; restart registers again")
        let core = KatanaCoreMIDI()
        let generation = core.generation
        var deliveries: [[UInt8]] = []
        core.received = { deliveries.append($0) }
        core.deliver([1], generation: generation)
        core.stop()
        core.deliver([2], generation: generation)
        core.deliver([3], generation: core.generation)
        precondition(deliveries == [[1], [3]], "Queued CoreMIDI generation discarded")
        let midi = FakeMIDILayer()
        let transport = KatanaMIDITransport(midi: midi)
        transport.start()
        for restart in [true, false] {
            let oldReceive = midi.received!
            if restart {
                transport.stop()
                transport.start()
            } else {
                midi.endpoints = []
                midi.changed?()
                midi.endpoints = ["KATANA fake"]
                midi.changed?()
            }
            let count = midi.packets.count
            let pending = Task { try await transport.exchange(KatanaSysEx.read(0, count: 2)) }
            while midi.packets.count == count { await Task.yield() }
            oldReceive(try KatanaSysEx.write(0, [0, 1]))
            let current = try KatanaSysEx.write(0, [0, 5])
            midi.received?(Array(current.prefix(7)))
            midi.received?(Array(current.dropFirst(7)))
            let response = try KatanaSysEx.decode(await pending.value)
            precondition(response.data == [0, 5], "Stale callback completed current read")
        }
        transport.stop()
        do {
            try await transport.send(KatanaSysEx.write(0, [0, 5]))
            fatalError("Disconnected send accepted")
        } catch { precondition(error as? KatanaError == .unavailable) }
        print("PASS: stop/start and reconnect discard stale callbacks; fragmented current reply accepted")
    }

    static func virtualMIDI() async throws {
        var client: MIDIClientRef = 0
        let status = MIDIClientCreateWithBlock("Transport Probe" as CFString, &client, nil)
        guard status == noErr else {
            print("SKIP: CoreMIDI virtual round trip: MIDI client unavailable (\(status))")
            return
        }
        defer { MIDIClientDispose(client) }
        let name = "Transport Probe \(UUID().uuidString)"
        var source: MIDIEndpointRef = 0
        let sourceStatus = MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &source)
        guard sourceStatus == noErr else {
            print("SKIP: CoreMIDI virtual round trip: virtual source unavailable (\(sourceStatus))")
            return
        }
        let replySource = source
        var destination: MIDIEndpointRef = 0
        let destinationStatus = MIDIDestinationCreateWithProtocol(client, name as CFString, ._1_0,
            &destination, { @Sendable list, _ in
                precondition(MIDIReceivedEventList(replySource, list) == noErr)
            })
        guard destinationStatus == noErr else {
            print("SKIP: CoreMIDI virtual round trip: virtual destination unavailable (\(destinationStatus))")
            return
        }
        let midi = KatanaCoreMIDI()
        try midi.start()
        defer { midi.stop() }
        try midi.connect(name)
        var received: [UInt8] = []
        midi.received = { received += $0 }
        for count in [2, 128, 225] {
            received = []
            let body = try KatanaSysEx.bytes(0) + (0..<count).map { UInt8($0 % 128) }
            let packet = KatanaSysEx.header + [0x12] + body + [KatanaSysEx.checksum(body), 0xF7]
            try midi.send(packet)
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while received.count < packet.count && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            precondition(received == packet, "Virtual CoreMIDI reply must be byte-exact")
            print("PASS: virtual CoreMIDI \(count)-byte round trip through exact non-amp endpoint")
        }
    }
}
