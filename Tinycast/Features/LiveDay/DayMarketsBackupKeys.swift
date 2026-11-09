import Foundation

extension NotchcastFeature.BackupKeys {
    static let dayMarkets = Self(allowed: [
        "notchcast.day.marketSymbols": .strings(100, 64),
    ], excluded: [])
}
