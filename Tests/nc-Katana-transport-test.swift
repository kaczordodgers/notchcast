// notchcast-sources: Tinycast/Features/Katana/Model/*.swift Tinycast/Features/Katana/Service/*.swift
import Foundation

@MainActor
final class FakeMIDILayer: KatanaMIDILayer {
    var endpoints = ["KATANA fake"]
    var changed: (() -> Void)?
    var received: (([UInt8]) -> Void)?
    var packets: [[UInt8]] = []
    func start() throws {}
    func stop() {}
    func connect(_ name: String) throws { precondition(name == "KATANA fake") }
    func send(_ bytes: [UInt8]) throws { packets.append(bytes) }
}

@main @MainActor
struct KatanaTransportTests {
    static func main() async throws {
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
}
