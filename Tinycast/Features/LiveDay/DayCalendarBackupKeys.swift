import Foundation

extension NotchcastFeature.BackupKeys {
    static let dayCalendar = Self(allowed: [
        "notchcast.day.excludedCalendars": .strings(500, 256),
    ], excluded: [])
}
