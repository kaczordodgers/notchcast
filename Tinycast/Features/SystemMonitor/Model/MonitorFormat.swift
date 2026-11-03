import Foundation

nonisolated struct MonitorFormat: Sendable, Equatable {
    let locale: Locale

    func percent(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        return (value / 100).formatted(.percent.precision(.fractionLength(0...1)).locale(locale))
    }

    func bytes(_ value: Int64) -> String {
        value.formatted(.byteCount(style: .file).locale(locale))
    }

    func bytesPerSecond(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        let bytes = Int64(value.rounded().clamped(to: -9.2e18...9.2e18))
        return bytes.formatted(.byteCount(style: .file).locale(locale)) + "/s"
    }

    func bitsPerSecond(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
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
        guard value.isFinite else { return "–" }
        return Measurement(value: value, unit: UnitTemperature.celsius).formatted(
            .measurement(width: .abbreviated, usage: .asProvided,
                         numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale))
    }

    func watts(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        return Measurement(value: value, unit: UnitPower.watts).formatted(
            .measurement(width: .abbreviated, usage: .asProvided,
                         numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale))
    }

    // The unit label is a localized string in the UI.
    func rpm(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}
