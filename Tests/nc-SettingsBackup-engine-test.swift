// notchcast-sources: Tinycast/Features/SettingsBackup/Model/*.swift Tinycast/Features/SettingsBackup/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
import Foundation
import Darwin

@main
struct SettingsBackupTest {
    static func main() async throws {
        let allowed = Set(ForkSettingsBackupSchema.allowed.keys)
        let excluded = ForkSettingsBackupSchema.excluded
        precondition(allowed.isDisjoint(with: excluded))
        for feature in NotchcastFeature.allCases {
            precondition(allowed.contains(feature.rawValue) != excluded.contains(feature.rawValue), feature.rawValue)
        }
        var original: [String: Any] = ["monitorCPU": 80, "islandHoverDelay": 0.3,
            "island": false, "greenMaximizeExcludedApps": "com.example.app",
            "notchcast.day.marketSymbols": ["BTC-USD"]]
        for key in excluded { original[key] = true }
        original["keepAwakeMinutes"] = 240
        original["fanMode"] = "manual"
        original["batteryChargePercent"] = 95
        let data = try ForkSettingsBackupEngine.encode(original, created: .now)
        let decoded = try ForkSettingsBackupEngine.decode(data)
        precondition(decoded["monitorCPU"] as? Int == 80)
        precondition(decoded["island"] as? Bool == false)
        precondition(decoded["greenMaximizeExcludedApps"] as? String == "com.example.app")
        precondition(decoded["notchcast.day.marketSymbols"] as? [String] == ["BTC-USD"])
        for key in excluded { precondition(decoded[key] == nil, key) }
        var invalid = [Data(), Data("broken".utf8), try archive([:]), try archive(["monitorCPU": 70], version: 3),
            try archive(["monitorCPU": "bad"]), try archive(["monitorCPU": true]),
            try archive(["monitorCPU": 70.5]), try archive(["monitorCPU": 101]),
            try archive(["island": 1]), try archive(["keepAwakeMinutes": 45]),
            try archive(["islandHoverDelay": 0.4]), try archive(["future": true]),
            try archive(["notchcast.quitProtection.mode": "future"]),
            try archive(["notchcast.day.marketSymbols": [String(repeating: "x", count: 65)]]),
            try archive(["dictationCleanup": "{\"apiKey\":\"secret\"}"]),
            try archive(["monitorCPU": 70], extra: ["future": true])]
        for key in excluded { invalid.append(try archive(["monitorCPU": 70, key: true])) }
        for input in invalid {
            do { _ = try ForkSettingsBackupEngine.decode(input); preconditionFailure("Accepted invalid archive") } catch { }
        }
        let filtered = try ForkSettingsBackupEngine.decode(ForkSettingsBackupEngine.encode(
            ["monitorCPU": "bad", "island": true, "unknown": true], created: .now))
        precondition(filtered.count == 1 && filtered["island"] as? Bool == true)
        precondition(ForkSettingsBackupEngine.newest(in: ["settings-99999.plist"]) == nil)
        let newest = ForkSettingsBackupEngine.newest(in: ["settings-v2-9.plist", "settings-v2-10.plist"])
        precondition(newest == "settings-v2-10.plist")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await ForkSettingsBackupService.save(data, folder: folder, day: 1)
        try await ForkSettingsBackupService.save(Data(), folder: folder, day: 1)
        let saved = try await ForkSettingsBackupService.latest(folder: folder)
        precondition(saved == data)
        let fifo = folder.appendingPathComponent("settings-v2-2.plist")
        precondition(mkfifo(fifo.path, 0o600) == 0)
        do { _ = try await ForkSettingsBackupService.latest(folder: folder); preconditionFailure("Accepted FIFO") } catch { }
        try FileManager.default.removeItem(at: fifo)
        try Data(repeating: 0, count: ForkSettingsBackupEngine.maximumSize + 1).write(to: fifo)
        do {
            _ = try await ForkSettingsBackupService.latest(folder: folder)
            preconditionFailure("Accepted oversized file")
        } catch { }
        print("PASS: feature classification guard; Bool/Int/Double/String/array round trip")
        print("PASS: every excluded key omitted and refused; unknown nested/root keys and invalid values refused")
        print("PASS: v1 names ignored; daily first save preserved; FIFO and oversized newest refused")
    }

    static func archive(_ values: [String: Any], version: Int = 2, extra: [String: Any] = [:]) throws -> Data {
        var root: [String: Any] = ["format": version, "created": Date.now, "preferences": values]
        root.merge(extra) { _, new in new }
        return try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }
}
