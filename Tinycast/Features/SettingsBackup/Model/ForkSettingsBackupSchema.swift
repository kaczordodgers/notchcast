import Foundation
import CoreFoundation

enum ForkSettingsBackupSchema {
    indirect enum Value: Sendable {
        case bool
        case integer(ClosedRange<Double>)
        case number(ClosedRange<Double>)
        case choices([Double])
        case string(Int, [String] = [])
        case strings(Int, Int)
        case object([String: Value])
        case array(Int, Value)
        case json(Value)
        case optional(Value)
        case colors

        func accepts(_ value: Any) -> Bool {
            switch self {
            case .colors:
                guard let colors = value as? [String], colors.count == 12 else { return false }
                return colors.allSatisfy { color in
                    color.hasPrefix("#") && [7, 9].contains(color.count)
                        && color.dropFirst().utf8.allSatisfy {
                            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
                        }
                }
            case .optional(let wrapped):
                return value is NSNull || wrapped.accepts(value)
            case .bool:
                return (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
            case .integer(let range), .number(let range):
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, range.contains(number.doubleValue) else { return false }
                if case .integer = self { return number.doubleValue.rounded() == number.doubleValue }
                return true
            case .choices(let choices):
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
                return choices.contains(number.doubleValue)
            case .string(let limit, let choices):
                guard let string = value as? String else { return false }
                return string.count <= limit && (choices.isEmpty || choices.contains(string))
            case .strings(let count, let length):
                guard let strings = value as? [String] else { return false }
                return strings.count <= count && strings.allSatisfy { $0.count <= length }
            case .object(let fields):
                guard let object = value as? [String: Any], Set(object.keys).isSubset(of: Set(fields.keys)) else { return false }
                return fields.allSatisfy { $0.value.accepts(object[$0.key] ?? NSNull()) }
            case .array(let limit, let element):
                guard let array = value as? [Any], array.count <= limit else { return false }
                return array.allSatisfy(element.accepts)
            case .json(let shape):
                guard let string = value as? String, string.utf8.count <= 262_144,
                      let object = try? JSONSerialization.jsonObject(
                        with: Data(string.utf8), options: .fragmentsAllowed) else { return false }
                return shape.accepts(object)
            }
        }
    }

    static let theme: Value = .object([
        "name": .string(256), "author": .string(256), "appearance": .string(5, ["light", "dark"]),
        "colors": .colors,
    ])
    static let place: Value = .object([
        "name": .string(256), "country": .optional(.string(256)),
        "latitude": .number(-90...90), "longitude": .number(-180...180),
    ])
    static let cleanup: Value = .object([
        "effort": .string(6, ["low", "medium", "high"]),
        "promptAddition": .string(16_384), "vocabulary": .array(500, .object([
            "spelling": .string(256), "misheardForms": .strings(50, 256),
        ])),
    ])

    static let allowed: [String: Value] = [
        "island": .bool,
        "islandExternalDisplays": .bool,
        "islandFullScreen": .bool,
        "islandHoverOpen": .bool,
        "islandStatusMessages": .bool,
        "islandLiveActivities": .bool,
        "launcherFromIsland": .bool,
        "launcherNumberKeys": .bool,
        "launcherAliasSpace": .bool,
        "pastePlain": .bool,
        "agentPricing": .bool,
        "colorPicker": .bool,
        "finderCutPaste": .bool,
        "finderRename": .bool,
        "pasteImage": .bool,
        "monitorAlerts": .bool,
        "lowDiskWarning": .bool,
        "systemNotices": .bool,
        "volumeLevels": .bool,
        "displayBrightness": .bool,
        "quitProtection": .bool,
        "liveTimers": .bool,
        "dayCalendar": .bool,
        "dayWeather": .bool,
        "dayMarkets": .bool,
        "dictationIslandHUD": .bool,
        "settingsBackup": .bool,
        "showDesktop": .bool,
        "musicNowPlaying": .bool,
        "musicLastPlayer": .bool,
        "inUseMarks": .bool,
        "quickLookSpace": .bool,
        "markdownFiles": .bool,
        "plainTextFiles": .bool,
        "editorSpellChecking": .bool,
        "hideCommandM": .bool,
        "middleClick": .bool,
        "greenMaximize": .bool,
        "eventReminder": .bool,
        "switcherQuitKey": .bool,
        "linkQuickFixes": .bool,
        "launcherAnswers": .bool,
        "copyPath": .bool,
        "distillTimestamps": .bool,
        "distillConvert": .bool,
        "urlCleaner": .bool,
        "convertFiles": .bool,
        "mediaTools": .bool,
        "buildStats": .bool,
        "backupStatus": .bool,
        "buildStatsPath": .string(4096),
        "backupStatusPath": .string(4096),
        "greenMaximizeExcludedApps": .string(16_384),
        "monitorCPU": .integer(10...100),
        "monitorTemperature": .integer(40...110),
        "monitorMemory": .integer(0...1),
        "monitorDisk": .integer(1...50),
        "monitorBattery": .integer(1...50),
        "notchcast.colorPicker.format": .string(14, ["hex", "hexLowercase", "rgb", "hsl", "swiftUIColor", "nsColorLiteral"]),
        "islandHoverDelay": .choices([0.1, 0.3, 0.5, 1]),
        "notchcast.liveTimer.defaultDuration": .choices([300, 600, 900, 1500, 1800, 3600]),
        "notchcast.liveTimer.playSound": .bool,
        "notchcast.quitProtection.quitEnabled": .bool,
        "notchcast.quitProtection.closeEnabled": .bool,
        "notchcast.quitProtection.mode": .string(11, ["hold", "doublePress"]),
        "notchcast.quitProtection.exceptions": .strings(500, 256),
        "notchcast.day.marketSymbols": .strings(100, 64),
        "notchcast.day.excludedCalendars": .strings(500, 256),
        "notchcast.day.weatherPlace": .json(.optional(place)),
        "dictationCleanup": .json(cleanup),
        "notchcast.editor.font": .string(13, ["system", "jetBrainsMono"]),
        "notchcast.editor.theme": .string(10, ["system", "githubDark"]),
        "notchcast.editor.pairsAutomatically": .bool,
        "notchcast.appearance.surface": .string(5, ["glass", "black", "matte"]),
        "notchcast.appearance.theme.backgroundOpacity": .number(0.2...1),
        "notchcast.appearance.theme.light": .json(.optional(theme)),
        "notchcast.appearance.theme.dark": .json(.optional(theme)),
        "notchcast.appearance.themes.imported": .json(.array(100, theme)),
    ]

    static let excluded: Set<String> = [
        "spacesOrder",
        "aiUsage",
        "aiUsageOtherMac",
        "machLink",
        "machRemote",
        "linkHealth",
        "shelfBetweenMacs",
        "sendFiles",
        "updateRemote",
        "machBlockedDialogAlert",
        "remoteScreen",
        "machMBPFans",
        "remoteMacAddress",
        "remoteTerminalDirectory",
        "remoteUpdatePath",
        "aiUsageCachePath",
        "musicBlockAppleMusic",
        "spotifyConnect",
        "microphoneMute",
        "archives",
        "githubSearch",
        "clearNotifications",
        "smallCommands",
        "downloads",
        "downloadsAria2",
        "distill",
        "commandRunner",
        "archivesDefaultApp",
        "torrents",
        "agentSessions",
        "torrentsUseIPhone",
        "torrentsKeepSharing",
        "tasks",
        "archivesInPlace",
        "machineSetupProfile",
        "backupRunNow",
        "backupBrowseRestore",
        "music.lastPlayer",
        "spotify.deviceName",
        "microphone.muted",
        "microphone.muted.restore",
        "archiveHandlersClaimed",
        "archiveRecoveryParents",
        "systemMonitor",
        "screenshot",
        "notchcast.screenshot.destination",
        "notchcast.screenshot.folder",
        "keepAwake",
        "keepAwakeMinutes",
        "fanControl",
        "batteryChargeLimit",
        "batterySailing",
        "batteryHeatProtection",
        "batteryCalibration",
        "lidClosedAwake",
        "agentConfirmation",
        "fanMode",
        "batteryChargePercent",
        "agentActionGrants",
        "notchcast.liveTimer.entries",
        "notchcast.lowDisk.isLow",
        "spacesOrderOriginal",
    ]
}
