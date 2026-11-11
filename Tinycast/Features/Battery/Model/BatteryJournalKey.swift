extension BatteryOwnershipJournal {
    /// Raw values are the keys of the persisted journal and of `batteryDirtyVerbs`; never rename one.
    enum Key: String, CaseIterable, Sendable {
        case chargeLimit = "charge-limit"
        case charging = "battery-charging"
        case adapter = "battery-adapter"
        case sleep = "battery-sleep"

        /// Repair order, and the sorted order `batteryDirtyVerbs` has always been saved in.
        static let released: [Key] = [.adapter, .charging, .sleep]

        /// The verb that hands the effect back; the limit restores its captured value instead.
        var release: RootContract.Command? {
            switch self {
            case .chargeLimit: nil
            case .charging: .batteryChargingOn
            case .adapter: .batteryAdapterOn
            case .sleep: .batterySleepOn
            }
        }
    }

    func effect(_ key: Key) -> Effect? { effects[key.rawValue] }
}

extension RootContract.Command {
    var batteryJournalKey: BatteryOwnershipJournal.Key? {
        switch self {
        case .chargeLimit60, .chargeLimit70, .chargeLimit80, .chargeLimit90, .chargeLimitOff: .chargeLimit
        case .batteryChargingOn, .batteryChargingOff: .charging
        case .batteryAdapterOn, .batteryAdapterOff: .adapter
        case .batterySleepOn, .batterySleepOff: .sleep
        default: nil
        }
    }

    var chargeLimitPercent: Int? {
        switch self {
        case .chargeLimit60: 60
        case .chargeLimit70: 70
        case .chargeLimit80: 80
        case .chargeLimit90: 90
        default: nil
        }
    }
}
