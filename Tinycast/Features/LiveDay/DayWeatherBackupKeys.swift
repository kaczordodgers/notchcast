import Foundation

extension NotchcastFeature.BackupKeys {
    static let dayWeather = Self(allowed: [
        "notchcast.day.weatherPlace": .json(.optional(place)),
    ], excluded: [])

    private static let place: NotchcastFeature.BackupValue = .object([
        "name": .string(256), "country": .optional(.string(256)),
        "latitude": .number(-90...90), "longitude": .number(-180...180),
    ])
}
