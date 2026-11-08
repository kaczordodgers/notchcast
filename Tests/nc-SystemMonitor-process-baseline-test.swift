import Foundation

@main
struct SystemMonitorProcessBaselineTests {
    static func counter(_ pid: Int32, start: UInt64 = 1, ticks: UInt64) -> ProcessReading.Counter {
        .init(identity: .init(pid: pid, startSeconds: start, startMicroseconds: 0), name: "p\(pid)",
              cpuTicks: ticks, residentBytes: 0, sampledAt: 0)
    }

    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures += 1; print("FAIL: \(message)") }
        }
        let low = counter(10, ticks: 1), high = counter(900, ticks: 1), dead = counter(500, ticks: 1)
        let previous = [low.identity: low, high.identity: high, dead.identity: dead]
        let lowNow = counter(10, ticks: 5), reused = counter(900, start: 2, ticks: 3)

        let cut = ProcessSampler.baselines(previous: previous, reached: [lowNow], live: [10, 900])
        expect(cut[high.identity] == high, "unreached live PID keeps its baseline at the deadline")
        expect(cut[low.identity] == lowNow, "reached PID takes the new counter")
        expect(cut[dead.identity] == nil, "dead PID is dropped")
        expect(cut.count == 2, "only live PIDs remain")

        let next = ProcessSampler.baselines(previous: cut, reached: [lowNow, reused], live: [10, 900])
        expect(next[high.identity] == nil && next[reused.identity] == reused, "reused PID replaces old identity")

        var cursor: Int32 = 0, rankedPast = false
        for _ in 0..<4 where !rankedPast {
            var budget = 3
            let scan = ProcessSampler.scan(Array(1...10), after: cursor, read: { counter($0, ticks: 1) }) {
                budget -= 1
                return budget >= 0
            }
            cursor = scan.cursor
            rankedPast = scan.reached.contains { $0.identity.pid == 10 }
        }
        expect(rankedPast, "PID past the deadline cut is reached within ceil(10 / 3) samples")

        print(failures == 0 ? "all passed" : "\(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
