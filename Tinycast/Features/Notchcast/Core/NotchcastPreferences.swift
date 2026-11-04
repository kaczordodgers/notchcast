import Foundation
import Observation

@MainActor
@Observable
final class NotchcastPreferences {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onCommandsChanged: (() -> Void)?
    private var off: Set<NotchcastFeature>
    private var chargePercent: Int
    private var awakeDuration: Int
    var remoteMacAddress: String { didSet { defaults.set(remoteMacAddress, forKey: "remoteMacAddress") } }
    var remoteTerminalDirectory: String { didSet { defaults.set(remoteTerminalDirectory, forKey: "remoteTerminalDirectory") } }
    var remoteUpdatePath: String { didSet { defaults.set(remoteUpdatePath, forKey: "remoteUpdatePath") } }
    var backupStatusPath: String { didSet { defaults.set(backupStatusPath, forKey: "backupStatusPath") } }
    var aiUsageCachePath: String { didSet { defaults.set(aiUsageCachePath, forKey: "aiUsageCachePath") } }
    var greenMaximizeExcludedApps: String { didSet { defaults.set(greenMaximizeExcludedApps, forKey: "greenMaximizeExcludedApps") } }
    var islandHoverDelay: HoverDelay { didSet { defaults.set(islandHoverDelay.rawValue, forKey: "islandHoverDelay") } }
    var fanMode: String { didSet { defaults.set(fanMode, forKey: "fanMode") } }
    var buildStatsPath: String { didSet { defaults.set(buildStatsPath, forKey: "buildStatsPath") } }
    var monitorCPU: Int { didSet { defaults.set(monitorCPU, forKey: "monitorCPU") } }
    var monitorTemperature: Int { didSet { defaults.set(monitorTemperature, forKey: "monitorTemperature") } }
    var monitorMemory: Int { didSet { defaults.set(monitorMemory, forKey: "monitorMemory") } }
    var monitorDisk: Int { didSet { defaults.set(monitorDisk, forKey: "monitorDisk") } }
    var monitorBattery: Int { didSet { defaults.set(monitorBattery, forKey: "monitorBattery") } }
    var batteryChargePercent: Int { get { chargePercent } set { chargePercent = Self.chargeLimits.last(where: { $0 <= newValue }) ?? 60; defaults.set(chargePercent, forKey: "batteryChargePercent") } }
    var keepAwakeMinutes: Int { get { awakeDuration } set { awakeDuration = Self.allowed(newValue, Self.awakeDurations, 60); defaults.set(awakeDuration, forKey: "keepAwakeMinutes") } }
    @ObservationIgnored private var versions: [NotchcastFeature: Int] = [:]

    var audioPriorityEnabled: Bool { get { isOn(.audioPriority) } set { set(.audioPriority, newValue) } }
    @ObservationIgnored var commandAvailabilityChanged: (() -> Void)?
    var batteryJournalData: Data? { get { defaults.data(forKey: "batteryOwnershipJournal") } set { defaults.set(newValue, forKey: "batteryOwnershipJournal") } }
    var fanJournalData: Data? { get { defaults.data(forKey: "fanOwnershipJournal") } set { defaults.set(newValue, forKey: "fanOwnershipJournal") } }
    var batteryCalibrationCompletedAt: Date? { get { defaults.object(forKey: "batteryCalibrationCompletedAt") as? Date } set { defaults.set(newValue, forKey: "batteryCalibrationCompletedAt") } }
    var batteryRootDirty: Bool { get { defaults.bool(forKey: "batteryRootDirty") } set { defaults.set(newValue, forKey: "batteryRootDirty") } }
    var batteryOwnsNativeLimit: Bool { get { defaults.bool(forKey: "batteryOwnsNativeLimit") } set { defaults.set(newValue, forKey: "batteryOwnsNativeLimit") } }
    var batteryDirtyVerbs: [String] { get { defaults.stringArray(forKey: "batteryDirtyVerbs") ?? [] } set { defaults.set(newValue, forKey: "batteryDirtyVerbs") } }
    var batteryOwnedLimit: Int { get { defaults.integer(forKey: "batteryOwnedLimit") } set { defaults.set(newValue, forKey: "batteryOwnedLimit") } }
    var batteryPriorLimit: Int { get { defaults.integer(forKey: "batteryPriorLimit") } set { defaults.set(newValue, forKey: "batteryPriorLimit") } }

    init(suiteName: String) {
        let defaults = UserDefaults(suiteName: suiteName)!
        self.defaults = defaults
        remoteMacAddress = defaults.string(forKey: "remoteMacAddress") ?? ""
        remoteTerminalDirectory = defaults.string(forKey: "remoteTerminalDirectory") ?? ""
        remoteUpdatePath = defaults.string(forKey: "remoteUpdatePath") ?? ""
        backupStatusPath = defaults.string(forKey: "backupStatusPath") ?? ""
        aiUsageCachePath = defaults.string(forKey: "aiUsageCachePath") ?? ""
        buildStatsPath = defaults.string(forKey: "buildStatsPath") ?? ""
        greenMaximizeExcludedApps = defaults.string(forKey: "greenMaximizeExcludedApps") ?? ""
        monitorCPU = Self.threshold(defaults, "monitorCPU", 90, 10...100)
        monitorTemperature = Self.threshold(defaults, "monitorTemperature", 90, 40...110)
        monitorMemory = Self.threshold(defaults, "monitorMemory", 1, 0...1)
        monitorDisk = Self.threshold(defaults, "monitorDisk", 10, 1...50)
        monitorBattery = Self.threshold(defaults, "monitorBattery", 15, 1...50)
        fanMode = defaults.string(forKey: "fanMode") ?? "auto"
        chargePercent = Self.chargeLimits.last(where: { $0 <= (defaults.object(forKey: "batteryChargePercent") as? Int ?? 80) }) ?? 60
        awakeDuration = Self.allowed(defaults.integer(forKey: "keepAwakeMinutes"), Self.awakeDurations, 60)
        islandHoverDelay = HoverDelay(rawValue: defaults.double(forKey: "islandHoverDelay")) ?? .standard
        off = Self.featuresOff(defaults)
    }

    func revision(_ feature: NotchcastFeature) -> Int { versions[feature, default: 0] }

    func isOn(_ feature: NotchcastFeature) -> Bool { !off.contains(feature) }
    func isEnabled(_ feature: NotchcastFeature) -> Bool {
        isOn(feature) && feature.dependencies.allSatisfy(isEnabled)
    }

    var engineDefaults: UserDefaults { defaults }

    var archiveHandlersClaimed: Bool { get { defaults.bool(forKey: "archiveHandlersClaimed") } set { defaults.set(newValue, forKey: "archiveHandlersClaimed") } }

    func set(_ feature: NotchcastFeature, _ enabled: Bool) {
        guard isOn(feature) != enabled else { return }
        defaults.set(enabled, forKey: feature.rawValue)
        versions[feature, default: 0] += 1
        if enabled { off.remove(feature) } else { off.insert(feature) }
        if [.keepAwake, .fanControl, .systemMonitor].contains(feature) { commandAvailabilityChanged?() }
        onCommandsChanged?()
    }
}

extension NotchcastPreferences {
    static let shared = NotchcastPreferences(suiteName: (Bundle.main.bundleIdentifier ?? "app.notchcast.dev") + ".notchcast")
    static let chargeLimits = [60, 70, 80, 90]
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
            !$0.isWired || !(defaults.object(forKey: $0.rawValue) as? Bool ?? $0.defaultEnabled)
        })
    }
}
