import Foundation

@MainActor
private final class MemoryStore: AudioPriorityStore {
    var values: [AudioPriorityDevice.Direction: AudioPriorityRanking] = [
        .output: .init(enabled: true, uids: ["high", "low"]),
        .input: .init(enabled: true, uids: ["mic-high", "mic-low"]),
    ]
    func ranking(for direction: AudioPriorityDevice.Direction) -> AudioPriorityRanking {
        values[direction]!
    }
    func save(_ ranking: AudioPriorityRanking, for direction: AudioPriorityDevice.Direction) {
        values[direction] = ranking
    }
}

@MainActor
private final class FakeTransport: AudioPriorityTransport {
    struct Failure: Error {}
    var inventory: [AudioPriorityDevice] = []
    var defaults: [AudioPriorityDevice.Direction: String] = [.output: "low", .input: "mic-low"]
    var writes: [String] = []
    var callback: (@Sendable () -> Void)?
    var fail = false
    var starts = 0
    var stops = 0
    var readCount = 0
    func devices() -> [AudioPriorityDevice] { readCount += 1; return inventory }
    func defaultUID(for direction: AudioPriorityDevice.Direction) -> String? { defaults[direction] }
    func setDefault(uid: String, for direction: AudioPriorityDevice.Direction) throws {
        writes.append(uid)
        if fail { throw Failure() }
        defaults[direction] = uid
        callback?()
    }
    func start(onChange: @escaping @Sendable () -> Void) {
        starts += 1
        callback = onChange
    }
    func stop() { stops += 1; callback = nil }
    func inventory(outputs: [String], inputs: [String] = ["mic-low"]) {
        inventory = outputs.map { .init(uid: $0, name: $0, direction: .output) }
            + inputs.map { .init(uid: $0, name: $0, direction: .input) }
        callback?()
    }
}

@main
struct AudioPriorityTests {
    @MainActor
    static func main() async throws {
        let transport = FakeTransport()
        let store = MemoryStore()
        var failures = 0
        let manager = AudioPriorityManager(transport: transport, store: store) { _ in failures += 1 }
        var successes = 0
        manager.succeeded = { successes += 1 }
        transport.inventory(outputs: ["low"])
        manager.start()
        manager.start()
        precondition(transport.starts == 1 && transport.writes.isEmpty)
        let reads1 = transport.readCount
        transport.inventory(outputs: ["low", "high"])
        await settle { transport.readCount > reads1 }
        precondition(transport.writes == ["high"] && successes == 1)
        let reads2 = transport.readCount
        transport.inventory(outputs: ["low"])
        await settle { transport.readCount > reads2 }
        precondition(transport.writes == ["high", "low"])
        precondition(store.values[.output]!.uids == ["high", "low"])
        let reads3 = transport.readCount
        transport.inventory(outputs: ["low", "unknown"])
        await settle { transport.readCount > reads3 }
        precondition(transport.writes.count == 2)
        precondition(store.values[.output]!.uids == ["high", "low", "unknown"])
        transport.defaults[.output] = "unknown"
        let reads4 = transport.readCount
        transport.callback?()
        await settle { transport.readCount > reads4 }
        precondition(transport.writes.count == 2)
        transport.defaults[.output] = "high"
        let reads5 = transport.readCount
        transport.inventory(outputs: ["high", "low", "unknown"])
        await settle { transport.readCount > reads5 }
        precondition(transport.writes.count == 2)
        let reads6 = transport.readCount
        transport.inventory(outputs: ["high", "low", "unknown"], inputs: ["mic-low", "mic-high"])
        await settle { transport.readCount > reads6 }
        precondition(transport.writes == ["high", "low", "mic-high"])
        precondition(transport.defaults[.output] == "high")
        store.values[.output]!.enabled = false
        let reads7 = transport.readCount
        transport.inventory(outputs: ["low", "unknown"], inputs: ["mic-low", "mic-high"])
        await settle { transport.readCount > reads7 }
        precondition(transport.writes.count == 3)
        store.values[.output]!.enabled = true
        transport.defaults[.output] = "low"
        transport.fail = true
        let reads8 = transport.readCount
        transport.inventory(outputs: ["high", "low"], inputs: ["mic-low", "mic-high"])
        await settle { transport.readCount > reads8 }
        let reads9 = transport.readCount
        transport.callback?()
        await settle { transport.readCount > reads9 }
        precondition(failures == 1 && transport.writes.count == 4 && successes == 3)
        let lateCallback = transport.callback
        manager.stop()
        manager.stop()
        lateCallback?()
        await settle()
        precondition(transport.stops == 1 && transport.writes.count == 4)
        manager.start()
        lateCallback?()
        await settle()
        precondition(transport.writes.count == 4)
        manager.stop()
        print("PASS: connect, disconnect, unknown, manual, no-op, independence, disabled, failure,")
        print("PASS: stopped/stale callbacks, idempotence; fake transport only")
    }

    @MainActor
    static func settle(until ready: () -> Bool) async {
        while !ready() {
            try? await Task.sleep(for: .milliseconds(10))
        }
        precondition(ready(), "Inventory callback did not arrive")
    }

    static func settle() async {
        try? await Task.sleep(for: .milliseconds(180))
    }
}
