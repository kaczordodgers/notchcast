import Foundation

@main
struct SMCRetryTests {
    static func main() {
        func check(_ label: String, _ value: Bool) {
            guard value else { print("FAIL: \(label)"); exit(1) }
        }
        let keys = ["Tg0a", "Tp01", "Tg1b"]
        var lookups: [UInt32: Int] = [:]
        var reader = SMCSensorReader(client: nil, brand: "Apple M1")
        func discover(failing: Set<UInt32>) {
            reader.discover(needsCPU: true, needsGPU: true,
                            deadline: ProcessInfo.processInfo.systemUptime + 1,
                            keyCount: { UInt32(keys.count) }) { index in
                lookups[index, default: 0] += 1
                return failing.contains(index) ? nil : keys[Int(index)]
            }
        }
        discover(failing: [0])
        check("first pass skips the failed key", reader.discoveredGPUKeys == ["Tg1b"])
        discover(failing: [])
        check("failed key found on a later read", reader.discoveredGPUKeys.contains("Tg0a"))
        check("cpu key kept", reader.discoveredCPUKeys == ["Tp01"])

        lookups = [:]
        var stuck = SMCSensorReader(client: nil, brand: "Apple M1")
        for _ in 0..<10 {
            stuck.discover(needsCPU: true, needsGPU: true,
                           deadline: ProcessInfo.processInfo.systemUptime + 1,
                           keyCount: { UInt32(keys.count) }) { index in
                lookups[index, default: 0] += 1
                return index == 0 ? nil : keys[Int(index)]
            }
        }
        check("permanently bad index is bounded", (lookups[0] ?? 0) <= 2)
        check("discovery still completes", stuck.discoveredGPUKeys == ["Tg1b"]
            && stuck.discoveredCPUKeys == ["Tp01"])
        print("SMC retry tests passed")
    }
}
