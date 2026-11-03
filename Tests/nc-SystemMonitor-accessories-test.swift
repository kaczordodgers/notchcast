import Foundation

@main
struct AccessoryTests {
    static func main() {
        var checks = 0
        func expect(_ value: Bool, _ label: String) {
            precondition(value, label)
            checks += 1
        }
        let mouse = AccessoryDevice(address: "AA:BB:CC:DD:EE:FF", name: "Mouse", majorClass: 5, minorClass: 32)
        let alias = AccessoryDevice(address: "aa-bb-cc-dd-ee-ff", name: "Mouse", majorClass: 5, minorClass: 32)
        var engine = AccessoryEngine(alreadyConnected: [mouse])
        expect(engine.connect(alias, at: 0) == nil, "registration baseline")
        engine.disconnect(mouse)
        expect(engine.connect(alias, at: 1) == .connected(alias), "reconnection")
        expect(engine.connect(mouse, at: 2) == nil, "duplicate while connected")
        engine.disconnect(mouse)
        expect(engine.connect(mouse, at: 1.399) == nil, "400ms merge")
        engine.disconnect(mouse)
        expect(engine.connect(mouse, at: 1.5) != nil, "outside merge window")
        var boundary = AccessoryEngine()
        expect(boundary.connect(mouse, at: 0) != nil, "first connect")
        boundary.disconnect(mouse)
        expect(boundary.connect(mouse, at: 0.4) != nil, "400ms boundary")
        for (name, kind) in [("AirPods Pro", AccessoryDevice.Kind.headphones), ("Keyboard", .keyboard),
                             ("Trackpad", .trackpad), ("Mouse", .mouse), ("Unknown", .other)] {
            expect(AccessoryDevice.kind(name: name) == kind, "name mapping")
            expect(!kind.symbol.isEmpty, "symbol")
        }
        expect(AccessoryDevice.kind(name: "", majorClass: 4, minorClass: 6) == .headphones, "audio class")
        expect(AccessoryDevice.kind(name: "", majorClass: 5, minorClass: 16) == .keyboard, "keyboard class")
        expect(AccessoryDevice.kind(name: "", majorClass: 5, minorClass: 32) == .mouse, "mouse class")
        func battery(_ percent: Double, id: UInt64 = 1) -> BatteryPeripheralReading {
            BatteryPeripheralReading(id: id, name: "Trackpad", percent: percent)
        }
        expect(engine.batteries([battery(21)]).isEmpty, "above threshold")
        expect(engine.batteries([battery(20)]) == [.lowBattery(battery(20), kind: .trackpad)], "20 fires")
        expect(engine.batteries([battery(19), battery(24)]).isEmpty, "episode holds")
        expect(engine.batteries([]).isEmpty, "missing sample")
        expect(engine.batteries([battery(10)]).isEmpty, "missing does not rearm")
        expect(engine.batteries([battery(.nan), battery(101), battery(-1)]).isEmpty, "invalid")
        expect(engine.batteries([battery(25)]).isEmpty, "25 rearms")
        expect(engine.batteries([battery(20), battery(20)]).count == 1, "one event per episode")
        expect(engine.batteries([battery(5, id: 2)]).count == 1, "independent devices")
        print("\(checks) passed, 0 failed; live Bluetooth service not started")
    }
}
