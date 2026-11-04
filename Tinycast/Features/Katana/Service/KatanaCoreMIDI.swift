import CoreMIDI
import Foundation

@MainActor
final class KatanaCoreMIDI: KatanaMIDILayer {
    var changed: (() -> Void)?
    var received: (([UInt8]) -> Void)?
    private var client: MIDIClientRef = 0
    private var input: MIDIPortRef = 0
    private var output: MIDIPortRef = 0
    private var source: MIDIEndpointRef = 0
    private var destination: MIDIEndpointRef = 0

    private func name(_ endpoint: MIDIEndpointRef) -> String {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &value) == noErr else { return "" }
        return value?.takeRetainedValue() as String? ?? ""
    }

    var endpoints: [String] {
        (0..<MIDIGetNumberOfDestinations()).map { name(MIDIGetDestination($0)) }.filter { target in
            (0..<MIDIGetNumberOfSources()).contains { name(MIDIGetSource($0)) == target }
        }
    }

    func start() throws {
        guard client == 0 else { return }
        guard MIDIClientCreateWithBlock("Notchcast Katana" as CFString, &client, { [weak self] _ in
            Task { @MainActor in self?.changed?() }
        }) == noErr else { throw KatanaError.unavailable }
        guard MIDIOutputPortCreate(client, "Katana Output" as CFString, &output) == noErr,
              MIDIInputPortCreateWithProtocol(client, "Katana Input" as CFString, ._1_0, &input,
                { [weak self] list, _ in
                    var bytes: [UInt8] = []
                    withUnsafePointer(to: list.pointee.packet) { first in
                        var packet = first
                        for _ in 0..<list.pointee.numPackets {
                            let words = withUnsafeBytes(of: packet.pointee.words) { Array($0.bindMemory(to: UInt32.self)) }
                            var index = 0
                            while index < Int(packet.pointee.wordCount) {
                                let word = words[index]
                                let type = word >> 28
                                let length = type == 3 || type == 4 ? 2 : type == 5 ? 4 : 1
                                if type == 3, index + 1 < Int(packet.pointee.wordCount) {
                                    let status = (word >> 20) & 15
                                    let count = min(Int((word >> 16) & 15), 6)
                                    let next = words[index + 1]
                                    let payload = [UInt8((word >> 8) & 255), UInt8(word & 255)]
                                        + [24, 16, 8, 0].map { UInt8((next >> $0) & 255) }
                                    if status == 0 || status == 1 { bytes.append(0xF0) }
                                    bytes += payload.prefix(count)
                                    if status == 0 || status == 3 { bytes.append(0xF7) }
                                }
                                index += length
                            }
                            packet = UnsafePointer(MIDIEventPacketNext(packet))
                        }
                    }
                    let received = bytes
                    Task { @MainActor in self?.received?(received) }
                }) == noErr else { stop(); throw KatanaError.unavailable }
    }

    func connect(_ target: String) throws {
        if source != 0 { MIDIPortDisconnectSource(input, source) }
        source = (0..<MIDIGetNumberOfSources()).map { MIDIGetSource($0) }.first { name($0) == target } ?? 0
        destination = (0..<MIDIGetNumberOfDestinations()).map { MIDIGetDestination($0) }
            .first { name($0) == target } ?? 0
        guard source != 0, destination != 0,
              MIDIPortConnectSource(input, source, nil) == noErr else { throw KatanaError.unavailable }
    }

    func send(_ bytes: [UInt8]) throws {
        guard destination != 0, bytes.first == 0xF0, bytes.last == 0xF7 else { throw KatanaError.unavailable }
        let payload = Array(bytes.dropFirst().dropLast())
        var list = MIDIEventList()
        var packet = MIDIEventListInit(&list, ._1_0)
        for offset in stride(from: 0, to: payload.count, by: 6) {
            let chunk = Array(payload[offset..<min(offset + 6, payload.count)])
            let last = offset + chunk.count == payload.count
            let status: UInt32 = offset == 0 ? (last ? 0 : 1) : (last ? 3 : 2)
            let padded = chunk + Array(repeating: UInt8(0), count: 6 - chunk.count)
            let words: [UInt32] = [0x30000000 | (status << 20) | (UInt32(chunk.count) << 16)
                | (UInt32(padded[0]) << 8) | UInt32(padded[1]),
                (UInt32(padded[2]) << 24) | (UInt32(padded[3]) << 16)
                | (UInt32(padded[4]) << 8) | UInt32(padded[5])]
            packet = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 2, words)
        }
        guard MIDISendEventList(output, destination, &list) == noErr else { throw KatanaError.unavailable }
    }

    func stop() {
        if client != 0 { MIDIClientDispose(client) }
        client = 0
        input = 0
        output = 0
        source = 0
        destination = 0
    }
}
