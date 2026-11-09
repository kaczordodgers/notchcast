import Foundation

@main
struct MonitorCoreTests {
    static func main() {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) {
            guard condition else { fatalError(message) }
            checks += 1
        }

        var history = MonitorHistory(capacity: 3)
        expect(history.values.isEmpty && history.latest == nil && history.min == nil, "empty")
        for value in [4.0, 1, 7, 2, 5] { history.append(value) }
        expect(history.values == [7, 2, 5], "ring ordering after wrapping")
        expect(history.min == 2 && history.max == 7 && history.latest == 5, "ring statistics")
        history.append(.nan)
        expect(history.values == [7, 2, 5], "invalid sample ignored")
        history.clear()
        history.append(9)
        expect(history.values == [9] && history.latest == 9, "clear resets index")
        var single = MonitorHistory(capacity: 1)
        single.append(1)
        single.append(2)
        expect(single.values == [2], "single capacity")

        let start = Date(timeIntervalSince1970: 0)
        var rule = MonitorAlertRule(direction: .above, threshold: 90, recoverValue: 80,
                                    sustainCount: 2, cooldown: 900)
        expect(rule.evaluate(91, at: start) == .none, "sustain first")
        expect(rule.evaluate(90, at: start) == .none, "threshold equality resets")
        expect(rule.evaluate(91, at: start) == .none, "sustain restarts")
        expect(rule.evaluate(92, at: start) == .fire, "sustained breach fires")
        expect(rule.evaluate(99, at: start.addingTimeInterval(1000)) == .none, "episode fires once")
        expect(rule.evaluate(85, at: start) == .none, "hysteresis holds")
        expect(rule.evaluate(80, at: start) == .none, "recovery equality rearms")
        expect(rule.evaluate(95, at: start.addingTimeInterval(899)) == .none, "sustain after recovery")
        expect(rule.evaluate(95, at: start.addingTimeInterval(899)) == .none, "cooldown suppresses")
        expect(rule.evaluate(95, at: start.addingTimeInterval(900)) == .fire, "cooldown boundary")
        var below = MonitorAlertRule(direction: .below, threshold: 10, recoverValue: 15,
                                     sustainCount: 1, cooldown: 0)
        expect(below.evaluate(9, at: start) == .fire, "below threshold")
        expect(below.evaluate(14, at: start) == .none, "below hysteresis")
        expect(below.evaluate(15, at: start) == .none, "below recovery")
        expect(below.evaluate(9, at: start) == .fire, "below rearms")
        var interrupted = MonitorAlertRule(direction: .above, threshold: 1, recoverValue: 0,
                                          sustainCount: 2)
        expect(interrupted.evaluate(2, at: start) == .none, "critical pressure first")
        expect(interrupted.evaluate(.infinity, at: start) == .none, "invalid breaks sustain")
        expect(interrupted.evaluate(2, at: start) == .none, "sustain reset on invalid")
        expect(interrupted.evaluate(2, at: start) == .fire, "critical pressure fires")

        expect(MonitorCadence.next(isVisible: false) == nil, "hidden stops sampling")
        expect(MonitorCadence.next(isVisible: true, baseInterval: 5)?.leeway == 0.5, "custom cadence")
        expect(MonitorCadence.next(isVisible: true, baseInterval: 0) == nil, "invalid cadence")

        for language in ["en", "de", "es", "fr", "ja", "ko", "pt", "ru", "zh-Hans"] {
            let format = MonitorFormat(locale: Locale(identifier: language))
            for output in [format.percent(12.5), format.bytes(1_000_000),
                           format.bytesPerSecond(1024), format.bitsPerSecond(8192),
                           format.celsius(42.5), format.watts(15.5), format.rpm(1200)] {
                expect(!output.isEmpty, "formatted output for \(language)")
            }
        }
        let english = MonitorFormat(locale: Locale(identifier: "en_US"))
        let german = MonitorFormat(locale: Locale(identifier: "de_DE"))
        for value in [Double.nan, .infinity, -.infinity] {
            expect(english.percent(value) == "–", "invalid percent")
            expect(english.celsius(value) == "–", "invalid temperature")
            expect(english.watts(value) == "–", "invalid power")
            expect(english.rpm(value) == "–", "invalid fan speed")
        }
        expect(english.percent(12.5).contains("12.5"), "percent uses 0 to 100 input")
        expect(german.percent(12.5).contains("12,5"), "injected decimal separator")
        expect(english.celsius(40).contains("40") && english.celsius(40).contains("C"), "keeps Celsius")
        expect(english.bitsPerSecond(8) != english.bytesPerSecond(8), "bits and bytes differ")
        expect(english.bytesPerSecond(1_500_000).contains("MB/s"), "byte rate scales")
        expect(english.bytesPerSecond(.infinity) == "–" && english.bytesPerSecond(.nan) == "–", "no crash on bad rate")
        expect(english.bitsPerSecond(.nan) == "–" && !english.bytesPerSecond(1e30).isEmpty, "rates clamp")
        expect(english.bitsPerSecond(250_000_000).contains("Mb"), "bit rate scales")
        print(english.bytesPerSecond(1_500_000), english.bitsPerSecond(250_000_000))
        print("\(checks) passed, 0 failed")
    }
}
