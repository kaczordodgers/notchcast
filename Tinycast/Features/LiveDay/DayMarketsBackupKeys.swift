import Foundation

extension NotchcastFeature.BackupKeys {
    static let dayMarkets = Self(allowed: [
        DayMarketsStore.symbolsKey: .strings(100, 64),
    ], excluded: [], snapshot: {
        [DayMarketsStore.symbolsKey: DayMarketsModule.shared.store.symbols]
    }, apply: { values in
        if let value = values[DayMarketsStore.symbolsKey] as? [String] { DayMarketsModule.shared.store.setSymbols(value) }
    })
}
