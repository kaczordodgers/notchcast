import Foundation

extension NotchcastPreferences {
    var batteryJournalData: Data? { get { engineDefaults.data(forKey: "batteryOwnershipJournal") } set { engineDefaults.set(newValue, forKey: "batteryOwnershipJournal") } }
    var batteryCalibrationCompletedAt: Date? { get { engineDefaults.object(forKey: "batteryCalibrationCompletedAt") as? Date } set { engineDefaults.set(newValue, forKey: "batteryCalibrationCompletedAt") } }
    var batteryRootDirty: Bool { get { engineDefaults.bool(forKey: "batteryRootDirty") } set { engineDefaults.set(newValue, forKey: "batteryRootDirty") } }
    var batteryOwnsNativeLimit: Bool { get { engineDefaults.bool(forKey: "batteryOwnsNativeLimit") } set { engineDefaults.set(newValue, forKey: "batteryOwnsNativeLimit") } }
    var batteryDirtyVerbs: [String] { get { engineDefaults.stringArray(forKey: "batteryDirtyVerbs") ?? [] } set { engineDefaults.set(newValue, forKey: "batteryDirtyVerbs") } }
    var batteryOwnedLimit: Int { get { engineDefaults.integer(forKey: "batteryOwnedLimit") } set { engineDefaults.set(newValue, forKey: "batteryOwnedLimit") } }
    var batteryPriorLimit: Int { get { engineDefaults.integer(forKey: "batteryPriorLimit") } set { engineDefaults.set(newValue, forKey: "batteryPriorLimit") } }
}
