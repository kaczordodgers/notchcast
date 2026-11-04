import Foundation
import Observation

@MainActor
@Observable
final class NotchcastPreferences {
    enum HoverDelay: Double, CaseIterable, Identifiable {
        case short = 0.1, standard = 0.3, medium = 0.5, long = 1
        var id: Double { rawValue }
        var title: String {
            Duration.seconds(rawValue).formatted(.units(
                allowed: [.seconds], width: .abbreviated,
                fractionalPart: .show(length: rawValue < 1 ? 1 : 0)))
        }
    }

    var islandHoverDelay: HoverDelay {
        didSet { defaults.set(islandHoverDelay.rawValue, forKey: "islandHoverDelay") }
    }
    var fanMode: String {
        didSet { defaults.set(fanMode, forKey: "fanMode") }
    }
    var monitorCPU: Int { didSet { defaults.set(monitorCPU, forKey: "monitorCPU") } }
    var monitorTemperature: Int { didSet { defaults.set(monitorTemperature, forKey: "monitorTemperature") } }
    var monitorMemory: Int { didSet { defaults.set(monitorMemory, forKey: "monitorMemory") } }
    var monitorDisk: Int { didSet { defaults.set(monitorDisk, forKey: "monitorDisk") } }
    var monitorBattery: Int { didSet { defaults.set(monitorBattery, forKey: "monitorBattery") } }
    static let chargeLimits = Array(stride(from: 50, through: 100, by: 5))
    static let awakeDurations = [15, 30, 60, 120, 240]
    private var chargePercent: Int
    var batteryChargePercent: Int {
        get { chargePercent }
        set {
            chargePercent = Self.chargeLimits.contains(newValue) ? newValue : 80
            defaults.set(chargePercent, forKey: "batteryChargePercent")
        }
    }
    private var awakeDuration: Int
    var keepAwakeMinutes: Int {
        get { awakeDuration }
        set {
            awakeDuration = Self.awakeDurations.contains(newValue) ? newValue : 60
            defaults.set(awakeDuration, forKey: "keepAwakeMinutes")
        }
    }
    static let shared = NotchcastPreferences(
        suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")

    @ObservationIgnored private let defaults: UserDefaults
    private var off: Set<NotchcastFeature>

    init(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName)!
        self.defaults = defaults
        func threshold(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
            let value = defaults.object(forKey: key) as? Int ?? fallback
            return min(range.upperBound, max(range.lowerBound, value))
        }
        monitorCPU = threshold("monitorCPU", 90, 10...100)
        monitorTemperature = threshold("monitorTemperature", 90, 40...110)
        monitorMemory = threshold("monitorMemory", 1, 0...1)
        monitorDisk = threshold("monitorDisk", 10, 1...50)
        monitorBattery = threshold("monitorBattery", 15, 1...50)
        fanMode = defaults.string(forKey: "fanMode") ?? "auto"
        let percent = defaults.integer(forKey: "batteryChargePercent")
        chargePercent = Self.chargeLimits.contains(percent) ? percent : 80
        let minutes = defaults.integer(forKey: "keepAwakeMinutes")
        awakeDuration = Self.awakeDurations.contains(minutes) ? minutes : 60
        islandHoverDelay = HoverDelay(rawValue: defaults.double(forKey: "islandHoverDelay")) ?? .standard
        off = Set(NotchcastFeature.allCases.filter {
            !(defaults.object(forKey: $0.rawValue) as? Bool ?? !$0.isSystemFeature)
        })
    }

    func isOn(_ feature: NotchcastFeature) -> Bool { !off.contains(feature) }

    func set(_ feature: NotchcastFeature, _ enabled: Bool) {
        guard isOn(feature) != enabled else { return }
        defaults.set(enabled, forKey: feature.rawValue)
        if enabled { off.remove(feature) } else { off.insert(feature) }
    }
}
