import Foundation

@main
struct AccessoryRowsTests {
    static func main() {
        let mouse = BatteryPeripheralReading(id: 2, name: "Mouse", percent: 42, isCharging: true)
        let keyboard = BatteryPeripheralReading(id: 1, name: "Keyboard", percent: 0)
        let invalid = BatteryPeripheralReading(id: 3, name: "Bad", percent: .nan)
        precondition(AccessoryBatteryRows.make([mouse, invalid, keyboard, mouse]) == [keyboard, mouse])
        precondition(AccessoryBatteryRows.make([]).isEmpty)
        precondition(AccessoryBatteryRows.make([.init(id: 4, name: "", percent: 50)]).isEmpty)
        precondition(AccessoryBatteryRows.make([.init(id: 4, name: "Bad", percent: 101)]).isEmpty)
        precondition(BatteryPeripheralReading.decode(id: 1, properties: [
            "Product": "Mouse", "BatteryPercent": 42, "Connected": false]) == nil)
        precondition(BatteryPeripheralReading.decode(id: 2, properties: [
            "Product": "Mouse", "BatteryPercent": 42, "BatteryIsCharging": true]) == mouse)
        precondition(keyboard.isCharging == nil)
        print("7 passed, 0 failed; fake readings only")
    }
}
