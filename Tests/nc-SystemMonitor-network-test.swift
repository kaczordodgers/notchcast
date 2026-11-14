import Foundation

@main
struct NetworkTests {
    static func main() throws {
        let interfaces: [NetworkInterfaceCandidate] = [
            .init(name: "en3", isRunning: true, hasAddress: false),
            .init(name: "utun0", isRunning: true, hasAddress: true),
            .init(name: "en0", isRunning: true, hasAddress: true),
            .init(name: "en1", isRunning: true, hasAddress: true),
            .init(name: "en2", isRunning: false, hasAddress: true)
        ]
        precondition(NetworkInterfaceCandidate.select(interfaces, primaryNames: ["utun0"]) == "en0")
        precondition(NetworkInterfaceCandidate.select(interfaces, primaryNames: ["en1", "en0"]) == "en1")
        precondition(NetworkInterfaceCandidate.select(interfaces, primaryNames: ["en2"]) == "en0")
        precondition(NetworkInterfaceCandidate.select(Array(interfaces.prefix(2)), primaryNames: []) == nil)
        var delta = NetworkDelta()
        func counter(_ received: UInt64, _ sent: UInt64, _ time: Double, _ name: String = "en0") -> NetworkDelta.Counter {
            .init(interface: name, received: received, sent: sent, time: time)
        }
        precondition(delta.update(counter(5_000_000_000, 100, 1)).down == nil)
        let rates = delta.update(counter(5_000_000_200, 200, 3))
        precondition(rates.down == 100 && rates.up == 50)
        precondition(delta.totalDown == 200 && delta.totalUp == 100)
        precondition(delta.update(counter(10, 10, 4)).down == 0)
        precondition(delta.totalDown == 200)
        precondition(delta.update(counter(30, 40, 5)).down == 20)
        precondition(delta.update(counter(999, 999, 6, "en1")).down == nil)
        precondition(delta.update(nil).down == nil)
        precondition(delta.update(counter(1000, 1000, 7)).down == nil)
        precondition(delta.update(counter(1001, 1001, 7)).down == nil)
        precondition(delta.update(counter(1002, 1002, .nan)).down == nil)
        var overflow = NetworkDelta()
        _ = overflow.update(counter(0, 0, 0))
        _ = overflow.update(counter(.max, .max, 1))
        _ = overflow.update(counter(0, 0, 2))
        _ = overflow.update(counter(5, 5, 3))
        precondition(overflow.totalDown == .max)
        let json = Data(#"{"dl_throughput":125000000,"ul_throughput":42000000,"responsiveness":1200,"base_rtt":12.5}"#.utf8)
        let result = try SpeedTestResult.parse(json)
        precondition(result.downloadMbps == 125 && result.uploadMbps == 42)
        precondition(result.responsivenessRPM == 1200 && result.baseRTTMilliseconds == 12.5)
        let minimal = try SpeedTestResult.parse(Data(#"{"dl_throughput":0,"ul_throughput":1}"#.utf8))
        precondition(minimal.responsivenessRPM == nil && minimal.baseRTTMilliseconds == nil)
        for invalid in ["{}", "[]", "invalid", #"{"dl_throughput":true,"ul_throughput":1}"#,
                        #"{"dl_throughput":-1,"ul_throughput":1}"#] {
            do {
                _ = try SpeedTestResult.parse(Data(invalid.utf8))
                preconditionFailure("Invalid JSON accepted")
            } catch {}
        }
        precondition(NetworkPublicIPService.parse("ip=203.0.113.1\n") == "203.0.113.1")
        precondition(NetworkPublicIPService.parse("ip=2001:db8::1\n") == "2001:db8::1")
        precondition(NetworkPublicIPService.parse("ip=bad\n") == nil)
        var sampler = NetworkSampler()
        if let reading = sampler.sample() {
            precondition(!reading.interface.isEmpty && reading.downBytesPerSecond == nil)
            precondition(reading.totalDown == 0 && reading.totalUp == 0)
        }
        print("ALL PASSED: network deltas, resets, totals, JSON, IP parsing, live sampler")
    }
}
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Service/*.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
