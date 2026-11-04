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
        try await virtualMIDI()
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
        print("Katana transport: absent/found, exact bytes, reply, reconnect, registration on/off passed")
    }

    static func virtualMIDI() async throws {
        var client: MIDIClientRef = 0
        precondition(MIDIClientCreateWithBlock("Katana Probe" as CFString, &client, nil) == noErr)
        defer { MIDIClientDispose(client) }
        var source: MIDIEndpointRef = 0
        precondition(MIDISourceCreateWithProtocol(client, "KATANA Probe" as CFString, ._1_0, &source) == noErr)
        let replySource = source
        let largeReply = try KatanaSysEx.write(KatanaSysEx.selectChannel, (0..<128).map { UInt8($0) })
        let payload = Array(largeReply.dropFirst().dropLast())
        var encoded: [UInt32] = []
        for offset in stride(from: 0, to: payload.count, by: 6) {
            let chunk = Array(payload[offset..<min(offset + 6, payload.count)])
            let status: UInt32 = offset == 0 ? 1 : offset + chunk.count == payload.count ? 3 : 2
            let padded = chunk + Array(repeating: UInt8(0), count: 6 - chunk.count)
            encoded += [0x30000000 | status << 20 | UInt32(chunk.count) << 16 | UInt32(padded[0]) << 8 | UInt32(padded[1]),
                UInt32(padded[2]) << 24 | UInt32(padded[3]) << 16 | UInt32(padded[4]) << 8 | UInt32(padded[5])]
        }
        let largeWords = encoded
        var destination: MIDIEndpointRef = 0
        precondition(MIDIDestinationCreateWithProtocol(client, "KATANA Probe" as CFString, ._1_0,
            &destination, { @Sendable list, _ in
                let capacity = 8192
                let storage = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 8)
                defer { storage.deallocate() }
                let reply = storage.bindMemory(to: MIDIEventList.self, capacity: 1)
                var tail = MIDIEventListInit(reply, ._1_0)
                let first = UnsafeRawPointer(list).advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
                    .assumingMemoryBound(to: MIDIEventPacket.self)
                var incoming = first
                for _ in 0..<list.pointee.numPackets {
                    let words = UnsafeRawPointer(incoming).advanced(by: MemoryLayout<MIDIEventPacket>.offset(of: \.words)!)
                        .assumingMemoryBound(to: UInt32.self)
                    let response = incoming.pointee.wordCount == 6 ? largeWords
                        : Array(UnsafeBufferPointer(start: words, count: Int(incoming.pointee.wordCount)))
                    for index in stride(from: 0, to: response.count, by: 2) {
                        tail = MIDIEventListAdd(reply, capacity, tail, UInt64(index + 1), 2, Array(response[index..<index + 2]))
                    }
                    incoming = UnsafePointer(MIDIEventPacketNext(incoming))
                }
                precondition(reply.pointee.numPackets > 1)
                precondition(MIDIReceivedEventList(replySource, reply) == noErr)
            }) == noErr)
        let midi = KatanaCoreMIDI()
        let transport = KatanaMIDITransport(midi: midi)
        transport.start()
        defer { transport.stop() }
        precondition(transport.connectionID != nil)
        for count in [2, 128, 225] {
            let data = (0..<count).map { UInt8($0 % 128) }
            let body = try KatanaSysEx.bytes(KatanaSysEx.selectChannel) + data
            let packet = KatanaSysEx.header + [0x12] + body + [KatanaSysEx.checksum(body), 0xF7]
            let reply = try await transport.exchange(packet)
            precondition(reply == (count == 2 ? largeReply : packet))
            let decoded = try KatanaSysEx.decode(reply)
            precondition(decoded.data == (count == 2 ? Array(0..<128).map { UInt8($0) } : data))
            print("Katana CoreMIDI: \(count)-byte write and separate-packet reply byte-exact")
        }
        transport.stop()
        transport.start()
        let packet = try KatanaSysEx.write(KatanaSysEx.selectChannel, [0, 5])
        let reply = try await transport.exchange(packet)
        precondition(reply == largeReply)
        print("Katana CoreMIDI: off → on → send passed")
    }
}
