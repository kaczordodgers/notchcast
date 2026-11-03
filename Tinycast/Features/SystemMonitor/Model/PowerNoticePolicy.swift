import Foundation

nonisolated struct PowerNoticePolicy: Sendable, Equatable {
    struct State: Sendable, Equatable {
        var lowBattery = false
        var highTemperature = false
    }

    var lowBatteryPercent: Double = 15
    var recoveryPercent: Double = 5
    var highTemperatureCelsius: Double = 40
    var temperatureRecovery: Double = 2

    func evaluate(_ battery: BatteryReading?, previous: State = State()) -> State {
        guard let battery else { return State() }
        let low = battery.onBattery && (battery.percent.map {
            $0 < lowBatteryPercent + (previous.lowBattery ? max(0, recoveryPercent) : 0)
        } ?? false)
        return State(lowBattery: low, highTemperature: battery.temperatureCelsius.map {
            $0 > highTemperatureCelsius - (previous.highTemperature ? max(0, temperatureRecovery) : 0)
        } ?? false)
    }
}
