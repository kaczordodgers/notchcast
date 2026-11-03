import Foundation

nonisolated struct MonitorFormat: Sendable, Equatable {
    let locale: Locale

    func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0...1)).locale(locale))
    }

    func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file).locale(locale))
    }

    func bytesPerSecond(_ value: Double) -> String {
        Int64(value.rounded()).formatted(.byteCount(style: .file).locale(locale)) + "/s"
    }

    func bitsPerSecond(_ value: Double) -> String {
        let unit: UnitInformationStorage = switch abs(value) {
        case 1e9...: .gigabits
        case 1e6...: .megabits
        case 1e3...: .kilobits
        default: .bits
        }
        return Measurement(value: value, unit: UnitInformationStorage.bits).converted(to: unit).formatted(
            .measurement(width: .abbreviated, usage: .asProvided,
                         numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale)) + "/s"
    }

    func celsius(_ value: Double) -> String {
        Measurement(value: value, unit: UnitTemperature.celsius).formatted(
            .measurement(width: .abbreviated, usage: .asProvided,
                         numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale))
    }

    func watts(_ value: Double) -> String {
        Measurement(value: value, unit: UnitPower.watts).formatted(
            .measurement(width: .abbreviated, usage: .asProvided,
                         numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale))
    }

    func rpm(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(locale)) + " RPM"
    }
}
