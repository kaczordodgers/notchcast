// notchcast-sources: Tinycast/Features/AccessoryNotices/Model/*.swift Tinycast/Features/AccessoryNotices/Service/*.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/BatteryPeripheralReading.swift
// notchcast-sources: Tinycast/Features/SystemMonitor/Model/AccessoryBatteryRows.swift
import Foundation

@MainActor
private final class FakeBluetooth: AccessoryBluetoothSource {
    var receive: ((String, String, Bool) -> Void)?
    func start(_ receive: @escaping (String, String, Bool) -> Void) -> [String] {
        self.receive = receive
        return ["AA:BB"]
    }
    func stop() { receive = nil }
}

@main struct AccessoryNoticeTests {
    @MainActor static func main() {
        var engine = AccessoryNoticeEngine()
        let source = FakeBluetooth()
        var connections = 0
        engine.seed(source.start { address, _, connected in
            if engine.connection(address, connected: connected) { connections += 1 }
        })
        source.receive?("aa-bb", "Mouse", true)
        source.receive?("cc:dd", "Mouse", true)
        source.receive?("CC-DD", "Mouse", true)
        assert(connections == 1)
        source.receive?("cc:dd", "Mouse", false)
        source.receive?("cc:dd", "Mouse", true)
        assert(connections == 2)
        source.stop()
        assert(source.receive == nil)
        func reading(_ percent: Double) -> [BatteryPeripheralReading] {
            [.init(id: 1, name: "Mouse", percent: percent)]
        }
        assert(engine.batteries(reading(21)).isEmpty)
        assert(engine.batteries(reading(20)).count == 1)
        assert(engine.batteries(reading(19)).isEmpty)
        assert(engine.batteries([]).isEmpty)
        assert(engine.batteries(reading(24)).isEmpty)
        assert(engine.batteries(reading(20)).isEmpty)
        assert(engine.batteries(reading(25)).isEmpty)
        assert(engine.batteries(reading(20)).count == 1)
        assert(engine.batteries(reading(.nan)).isEmpty)
        print("Accessory notices: all checks passed")
    }
}
