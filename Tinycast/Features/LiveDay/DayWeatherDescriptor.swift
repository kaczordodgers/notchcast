import Foundation

extension NotchcastFeature.Descriptor {
    static let dayWeather = Self(
        title: String(localized: "Weather"),
        subtitle: String(localized: "Forecast from Open-Meteo on the Day page.", table: "Notchcast"),
        group: .activities,
        defaultEnabled: true,
        dependencies: [.island],
        requiredGrants: [],
        isSystemFeature: false,
        isSystemTweak: false
    )
}
