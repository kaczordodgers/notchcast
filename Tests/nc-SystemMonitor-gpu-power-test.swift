import Foundation

@main
struct GPUPowerTests {
    static func main() {
        func check(_ label: String, _ value: Bool) {
            guard value else { print("FAIL: \(label)"); exit(1) }
        }
        check("missing battery", BatteryReading.decode(properties: [:]) == nil)
        check("desktop registry", BatteryReading.decode(properties: ["BatteryInstalled": false]) == nil)
        let raw: [String: Any] = [
            "BatteryInstalled": true, "CurrentCapacity": 14, "MaxCapacity": 100,
            "DesignCapacity": 5000, "AppleRawMaxCapacity": 4500, "CycleCount": 123,
            "Temperature": 4100, "Voltage": 12000, "Amperage": UInt32.max - 999,
            "ExternalConnected": false, "AvgTimeToEmpty": 90
        ]
        let battery = BatteryReading.decode(properties: raw)!
        check("capacity and health", abs((battery.percent ?? 0) - 14) < 0.001 && battery.healthPercent == 90)
        check("signed current", battery.watts == -12)
        check("temperature and time", battery.temperatureCelsius == 41 && battery.timeToEmptySeconds == 5400)
        check("cycles", battery.cycleCount == 123)
        var silicon = raw
        silicon["Temperature"] = nil
        silicon["BatteryData"] = ["Temperature": 3589]
        check("BatteryData temperature", BatteryReading.decode(properties: silicon)?.temperatureCelsius == 35.89)
        var charging = raw
        charging["ExternalConnected"] = true
        charging["IsCharging"] = true
        charging["Amperage"] = 2000
        charging["AvgTimeToFull"] = 30
        charging["AppleRawAdapterDetails"] = [["Watts": 67]]
        let charge = BatteryReading.decode(properties: charging)!
        check("charging", charge.isCharging && !charge.onBattery && charge.watts == 24)
        check("adapter and time", charge.adapterWatts == 67 && charge.timeToFullSeconds == 1800)
        check("no discharge time on AC", charge.timeToEmptySeconds == nil)
        charging["AvgTimeToFull"] = 65535
        check("unknown time", BatteryReading.decode(properties: charging)?.timeToFullSeconds == nil)
        let source: [String: Any] = ["Current Capacity": 50, "Max Capacity": 100,
                                     "Power Source State": "AC Power", "Is Charged": true]
        let full = BatteryReading.decode(properties: raw, source: source)!
        check("source precedence", full.percent == 50 && full.isCharged && !full.onBattery)
        check("GPU fallback", GPUReading.decode(id: 1, model: "Apple GPU", statistics:
            ["Device Utilization %": -1, "GPU Activity(%)": 42])?.utilizationPercent == 42)
        check("GPU absent", GPUReading.decode(id: 1, model: "Apple GPU", statistics: [:]) == nil)
        check("GPU nonfinite", GPUReading.decode(id: 1, model: "Apple GPU", statistics:
            ["Device Utilization %": Double.nan]) == nil)
        check("peripheral", BatteryPeripheralReading.decode(id: 1, properties:
            ["Product": "Mouse", "BatteryPercent": 72])?.percent == 72)
        check("invalid peripheral", BatteryPeripheralReading.decode(id: 1, properties:
            ["Product": "Mouse", "BatteryPercent": 101]) == nil)
        let start = ContinuousClock.now
        let liveBattery = BatteryService().read()
        let liveGPU = GPUService().read()
        let peripherals = BatteryPeripheralService().read()
        check("live battery", liveBattery?.percent.map { (0...100).contains($0) } ?? true)
        check("live GPU", liveGPU.allSatisfy { !$0.model.isEmpty && (0...100).contains($0.utilizationPercent) })
        check("live peripherals", peripherals.allSatisfy { (0...100).contains($0.percent) })
        print("Live reads: \(start.duration(to: .now)); GPU \(liveGPU.count), battery \(liveBattery != nil)")
        print("ALL PASSED")
    }
}
