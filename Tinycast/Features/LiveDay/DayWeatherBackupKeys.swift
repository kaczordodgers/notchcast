import Foundation

extension NotchcastFeature.BackupKeys {
    static let dayWeather = Self(allowed: [
        DayWeatherStore.placeKey: .json(.optional(place)),
    ], excluded: [], snapshot: {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let place = String(bytes: try encoder.encode(DayWeatherModule.shared.store.place), encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return [DayWeatherStore.placeKey: place]
    }, validate: { values in
        if let value = values[DayWeatherStore.placeKey] as? String { _ = try decoded(value) }
    }, apply: { values in
        if let value = values[DayWeatherStore.placeKey] as? String {
            DayWeatherModule.shared.store.select(try decoded(value))
        }
    })

    private static let place: NotchcastFeature.BackupValue = .object([
        "name": .string(256), "country": .optional(.string(256)),
        "latitude": .number(-90...90), "longitude": .number(-180...180),
    ])

    private static func decoded(_ value: String) throws -> DayWeatherPlace? {
        try JSONDecoder().decode(DayWeatherPlace?.self, from: Data(value.utf8))
    }
}
