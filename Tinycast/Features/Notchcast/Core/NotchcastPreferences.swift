import Foundation
import Observation

/// One stored setting per line and one init assignment per line, so branches that add a setting
/// merge by union. Types and helpers go in the extension below.
/// `notchcast/check-feature-shape.py` rejects a setting or an assignment a union merge kept twice.
@MainActor
@Observable
final class NotchcastPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    private var off: Set<NotchcastFeature>
    private var chargePercent: Int
    private var awakeDuration: Int
    var greenMaximizeExcludedApps: String { didSet { defaults.set(greenMaximizeExcludedApps, forKey: "greenMaximizeExcludedApps") } }
    var islandHoverDelay: HoverDelay { didSet { defaults.set(islandHoverDelay.rawValue, forKey: "islandHoverDelay") } }
    var fanMode: String { didSet { defaults.set(fanMode, forKey: "fanMode") } }
    var greenMaximizeExcludedApps: String {
        didSet { defaults.set(greenMaximizeExcludedApps, forKey: "greenMaximizeExcludedApps") }
    }
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
    var batteryJournalData: Data? {
        get { defaults.data(forKey: "batteryOwnershipJournal") }
        set { defaults.set(newValue, forKey: "batteryOwnershipJournal") }
    }
    var fanJournalData: Data? {
        get { defaults.data(forKey: "fanOwnershipJournal") }
        set { defaults.set(newValue, forKey: "fanOwnershipJournal") }
    }
    var monitorCPU: Int { didSet { defaults.set(monitorCPU, forKey: "monitorCPU") } }
    var monitorTemperature: Int { didSet { defaults.set(monitorTemperature, forKey: "monitorTemperature") } }
    var monitorMemory: Int { didSet { defaults.set(monitorMemory, forKey: "monitorMemory") } }
    var monitorDisk: Int { didSet { defaults.set(monitorDisk, forKey: "monitorDisk") } }
    var monitorBattery: Int { didSet { defaults.set(monitorBattery, forKey: "monitorBattery") } }
    var batteryChargePercent: Int { get { chargePercent } set { chargePercent = Self.allowed(newValue, Self.chargeLimits, 80); defaults.set(chargePercent, forKey: "batteryChargePercent") } }
    var keepAwakeMinutes: Int { get { awakeDuration } set { awakeDuration = Self.allowed(newValue, Self.awakeDurations, 60); defaults.set(awakeDuration, forKey: "keepAwakeMinutes") } }
    static let chargeLimits = Array(stride(from: 50, through: 100, by: 5))
    static let chargeLimits = [60, 70, 80, 90]
    var batteryCalibrationCompletedAt: Date? {
        get { defaults.object(forKey: "batteryCalibrationCompletedAt") as? Date }
        set { defaults.set(newValue, forKey: "batteryCalibrationCompletedAt") }
    }
    var batteryRootDirty: Bool {
        get { defaults.bool(forKey: "batteryRootDirty") }
        set { defaults.set(newValue, forKey: "batteryRootDirty") }
    }
    var batteryOwnsNativeLimit: Bool {
        get { defaults.bool(forKey: "batteryOwnsNativeLimit") }
        set { defaults.set(newValue, forKey: "batteryOwnsNativeLimit") }
    }
    var batteryDirtyVerbs: [String] {
        get { defaults.stringArray(forKey: "batteryDirtyVerbs") ?? [] }
        set { defaults.set(newValue, forKey: "batteryDirtyVerbs") }
    }
    var batteryOwnedLimit: Int {
        get { defaults.integer(forKey: "batteryOwnedLimit") }
        set { defaults.set(newValue, forKey: "batteryOwnedLimit") }
    }
    var batteryPriorLimit: Int {
        get { defaults.integer(forKey: "batteryPriorLimit") }
        set { defaults.set(newValue, forKey: "batteryPriorLimit") }
    }
    static let awakeDurations = [15, 30, 60, 120, 240]
    private var chargePercent: Int
    var batteryChargePercent: Int {
        get { chargePercent }
        set {
            chargePercent = Self.chargeLimits.last(where: { $0 <= newValue }) ?? 60
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
    let audioPriority: AudioPriorityPreferences
    var audioPriorityEnabled: Bool {
        get { isOn(.audioPriority) }
        set { set(.audioPriority, newValue) }
    }
    @ObservationIgnored var commandAvailabilityChanged: (() -> Void)?
    private var off: Set<NotchcastFeature>

    init(suiteName: String) {
        audioPriority = AudioPriorityPreferences(suiteName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        self.defaults = defaults
        greenMaximizeExcludedApps = defaults.string(forKey: "greenMaximizeExcludedApps") ?? ""
        monitorCPU = Self.threshold(defaults, "monitorCPU", 90, 10...100)
        monitorTemperature = Self.threshold(defaults, "monitorTemperature", 90, 40...110)
        monitorMemory = Self.threshold(defaults, "monitorMemory", 1, 0...1)
        monitorDisk = Self.threshold(defaults, "monitorDisk", 10, 1...50)
        monitorBattery = Self.threshold(defaults, "monitorBattery", 15, 1...50)
        fanMode = defaults.string(forKey: "fanMode") ?? "auto"
        chargePercent = Self.allowed(defaults.integer(forKey: "batteryChargePercent"), Self.chargeLimits, 80)
        awakeDuration = Self.allowed(defaults.integer(forKey: "keepAwakeMinutes"), Self.awakeDurations, 60)
        let percent = defaults.object(forKey: "batteryChargePercent") as? Int ?? 80
        chargePercent = Self.chargeLimits.last(where: { $0 <= percent }) ?? 60
        let minutes = defaults.integer(forKey: "keepAwakeMinutes")
        awakeDuration = Self.awakeDurations.contains(minutes) ? minutes : 60
        islandHoverDelay = HoverDelay(rawValue: defaults.double(forKey: "islandHoverDelay")) ?? .standard
        off = Self.featuresOff(defaults)
    }

    func isOn(_ feature: NotchcastFeature) -> Bool { !off.contains(feature) }

    func set(_ feature: NotchcastFeature, _ enabled: Bool) {
        guard isOn(feature) != enabled else { return }
        defaults.set(enabled, forKey: feature.rawValue)
        if enabled { off.remove(feature) } else { off.insert(feature) }
        if [.keepAwake, .fanControl, .systemMonitor].contains(feature) { commandAvailabilityChanged?() }
    }
}

extension NotchcastPreferences {
    static let shared = NotchcastPreferences(suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")
    static let chargeLimits = Array(stride(from: 50, through: 100, by: 5))
    static let awakeDurations = [15, 30, 60, 120, 240]

    enum HoverDelay: Double, CaseIterable, Identifiable {
        case short = 0.1, standard = 0.3, medium = 0.5, long = 1
        var id: Double { rawValue }
        var title: String {
            Duration.seconds(rawValue).formatted(.units(
                allowed: [.seconds], width: .abbreviated,
                fractionalPart: .show(length: rawValue < 1 ? 1 : 0)))
        }
    }

    private static func threshold(_ defaults: UserDefaults, _ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int {
        let value = defaults.object(forKey: key) as? Int ?? fallback
        return min(range.upperBound, max(range.lowerBound, value))
    }

    private static func allowed(_ value: Int, _ choices: [Int], _ fallback: Int) -> Int {
        choices.contains(value) ? value : fallback
    }

    private static func featuresOff(_ defaults: UserDefaults) -> Set<NotchcastFeature> {
        Set(NotchcastFeature.allCases.filter {
            !(defaults.object(forKey: $0.rawValue) as? Bool ?? $0.defaultEnabled)
        })
    }
}
