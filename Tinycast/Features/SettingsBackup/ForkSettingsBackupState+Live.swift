import Foundation

extension ForkSettingsBackupState {
    static var live: Self {
        Self(snapshot: {
            var values = ForkSettingsBackupRestore.snapshot(.shared)
            values.merge(quitValues(NotchcastCore.quitProtection)) { _, value in value }
            values["notchcast.liveTimer.defaultDuration"] = NotchcastCore.timers.store.defaultDuration
            values["notchcast.liveTimer.playSound"] = NotchcastCore.timers.store.playSoundWhenTimeIsUp
            values["notchcast.day.marketSymbols"] = NotchcastCore.markets.store.symbols
            values["notchcast.day.excludedCalendars"] = NotchcastCore.eventReminder.calendar.excludedCalendarIDs.sorted()
            values["notchcast.day.weatherPlace"] = try json(NotchcastCore.weather.store.place)
            let appearance = AppearanceStore()
            values["notchcast.appearance.surface"] = appearance.surfaceStyle.rawValue
            values["notchcast.appearance.theme.backgroundOpacity"] = appearance.backgroundOpacity
            values["notchcast.appearance.theme.light"] = try json(appearance.light)
            values["notchcast.appearance.theme.dark"] = try json(appearance.dark)
            values["notchcast.appearance.themes.imported"] = try json(appearance.imported)
            values["dictationCleanup"] = try json(cleanupStore.read())
            try validateLive(values)
            return values
        }, validate: validateLive, apply: { values in
            try validateLive(values)
            if let value = values["notchcast.liveTimer.defaultDuration"] as? Double {
                NotchcastCore.timers.store.defaultDuration = value
            }
            if let value = values["notchcast.liveTimer.playSound"] as? Bool {
                NotchcastCore.timers.store.playSoundWhenTimeIsUp = value
            }
            applyQuit(values, to: NotchcastCore.quitProtection)
            if let value = values["notchcast.day.marketSymbols"] as? [String] { NotchcastCore.markets.store.setSymbols(value) }
            if let value = values["notchcast.day.excludedCalendars"] as? [String] {
                NotchcastCore.eventReminder.calendar.setExcludedCalendars(Set(value))
            }
            if let value = values["notchcast.day.weatherPlace"] as? String {
                NotchcastCore.weather.store.select(try decode(DayWeatherPlace?.self, value))
            }
            let appearance = AppearanceStore()
            if let value = values["notchcast.appearance.surface"] as? String,
               let style = AppearanceSurfaceStyle(rawValue: value) { appearance.surfaceStyle = style }
            if let value = values["notchcast.appearance.theme.backgroundOpacity"] as? Double {
                appearance.backgroundOpacity = value
            }
            if let value = values["notchcast.appearance.themes.imported"] as? String {
                try appearance.replaceImported(decode([RaycastTheme].self, value))
            }
            if let value = values["notchcast.appearance.theme.light"] as? String {
                try appearance.select(decode(RaycastTheme?.self, value), for: .light)
            }
            if let value = values["notchcast.appearance.theme.dark"] as? String {
                try appearance.select(decode(RaycastTheme?.self, value), for: .dark)
            }
            if let value = values["dictationCleanup"] as? String {
                try cleanupStore.save(decode(DictationCleanupSettings.self, value))
            }
            try ForkSettingsBackupRestore.apply(values, to: .shared)
        })
    }

    private static var cleanupStore: DictationCleanupSettingsStore {
        let identifier = Bundle.main.bundleIdentifier ?? "app.notchcast.dev"
        return DictationCleanupSettingsStore(defaults: DayStorage.defaults, bundleIdentifier: identifier)
    }

    private static func json(_ value: some Encodable) throws -> String {
        guard let string = String(bytes: try JSONEncoder().encode(value), encoding: .utf8) else {
            throw ForkSettingsBackupEngine.Failure.invalidArchive
        }
        return string
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, _ value: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(value.utf8))
    }

    private static func validateLive(_ values: [String: Any]) throws {
        try ForkSettingsBackupEngine.validate(values)
        for (key, appearance) in [("notchcast.appearance.theme.light", RaycastTheme.Appearance.light),
                                  ("notchcast.appearance.theme.dark", .dark)] {
            if let value = values[key] as? String, let theme = try decode(RaycastTheme?.self, value),
               theme.appearance != appearance { throw ForkSettingsBackupEngine.Failure.invalidArchive }
        }
        if let value = values["notchcast.appearance.themes.imported"] as? String { _ = try decode([RaycastTheme].self, value) }
        if let value = values["notchcast.day.weatherPlace"] as? String { _ = try decode(DayWeatherPlace?.self, value) }
        if let value = values["dictationCleanup"] as? String { _ = try decode(DictationCleanupSettings.self, value) }
    }
}
