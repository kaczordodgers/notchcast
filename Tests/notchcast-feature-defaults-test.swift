// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift Tinycast/Features/Notchcast/Core/NotchcastFeature+Logic.swift
// Pins existing defaults and needsIsland; changing one means editing this table in plain sight.
let pinned: [String: Bool] = [
    "island": true,
    "islandExternalDisplays": true,
    "islandFullScreen": true,
    "islandHoverOpen": true,
    "islandStatusMessages": true,
    "islandLiveActivities": true,
    "launcherFromIsland": true,
    "launcherNumberKeys": false,
    "launcherAliasSpace": false,
    "systemMonitor": false,
    "fanControl": false,
    "monitorAlerts": false,
    "lowDiskWarning": true,
    "systemNotices": true,
    "volumeLevels": true,
    "displayBrightness": true,
    "quitProtection": true,
    "liveTimers": true,
    "dayCalendar": true,
    "dayWeather": true,
    "dayMarkets": true,
    "dictationIslandHUD": true,
    "batteryChargeLimit": false,
    "batterySailing": false,
    "batteryHeatProtection": false,
    "batteryCalibration": false,
    "keepAwake": false,
    "lidClosedAwake": false,
    "settingsBackup": true,
    "showDesktop": true,
    "spacesOrder": false,
    "hideCommandM": true,
    "middleClick": true,
    "greenMaximize": true,
    "machineSetupProfile": true,
    "agentConfirmation": true,
    "eventReminder": true,
    "switcherQuitKey": false,
    "linkQuickFixes": false,
    "buildStats": false,
    "pastePlain": false,
    "finderCutPaste": true,
    "finderRename": true,
    "pasteImage": true,
    "colorPicker": true,
    "screenshot": true,
    "musicNowPlaying": true,
    "musicLastPlayer": true,
    "musicBlockAppleMusic": true,
    "spotifyConnect": false,
    "microphoneMute": true,
    "inUseMarks": true,
    "archives": true,
    "archivesInPlace": false,
    "archivesDefaultApp": false,
    "torrents": true,
    "torrentsUseIPhone": true,
    "torrentsKeepSharing": false,
]

let pinnedIsland: Set<String> = [
    "island",
    "islandExternalDisplays",
    "islandFullScreen",
    "islandHoverOpen",
    "islandStatusMessages",
    "islandLiveActivities",
    "launcherFromIsland",
    "musicNowPlaying",
    "musicLastPlayer",
    "musicBlockAppleMusic",
    "spotifyConnect",
    "microphoneMute",
    "inUseMarks",
    "lowDiskWarning",
    "systemNotices",
    "volumeLevels",
    "liveTimers",
    "dayCalendar",
    "dayWeather",
    "dayMarkets",
    "dictationIslandHUD",
    "agentConfirmation",
    "eventReminder",
]

@main
enum FeatureDefaultsTest {
    static func main() {
        var checked = 0
        for feature in NotchcastFeature.allCases {
            guard let expected = pinned[feature.rawValue] else { continue }
            precondition(feature.defaultEnabled == expected,
                         "\(feature.rawValue) default flipped to \(feature.defaultEnabled); pinned \(expected)")
            precondition(feature.needsIsland == pinnedIsland.contains(feature.rawValue),
                         "\(feature.rawValue) needsIsland flipped to \(feature.needsIsland)")
            checked += 1
        }
        let removed = Set(pinned.keys).subtracting(NotchcastFeature.allCases.map(\.rawValue))
        precondition(removed.isEmpty, "pinned features no longer exist: \(removed.sorted()); remove them here on purpose")
        print("PASS: \(checked) pinned feature defaults unchanged; \(NotchcastFeature.allCases.count - checked) new features unpinned")
    }
}
