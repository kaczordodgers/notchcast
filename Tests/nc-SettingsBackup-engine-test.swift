// notchcast-sources: Tinycast/Features/SettingsBackup/Model/*.swift Tinycast/Features/SettingsBackup/Service/*.swift
import Foundation

@main
struct SettingsBackupTest {
    static func main() async throws {
        let original: [String: Any] = ["monitorCPU": 80, "islandHoverDelay": 0.3,
                                       "unknown": "preserve", "fanControl": true]
        let data = try ForkSettingsBackupEngine.encode(original, created: Date(timeIntervalSince1970: 0))
        let restored = try ForkSettingsBackupEngine.restored(data, current: ["unknown": "local", "fanControl": false])
        precondition(restored["monitorCPU"] as? Int == 80)
        precondition(restored["islandHoverDelay"] as? Double == 0.3)
        precondition(restored["unknown"] as? String == "local")
        precondition(restored["fanControl"] as? Bool == false)
        for invalid in [Data("broken".utf8), Data(), try archive(["monitorCPU": "bad"]),
                        try archive(["monitorCPU": true]), try archive(["monitorCPU": 101]),
                        try archive([:], version: 2)] {
            do {
                _ = try ForkSettingsBackupEngine.restored(invalid, current: original)
                preconditionFailure("Accepted corrupt input")
            } catch { }
        }
        let unknown = try ForkSettingsBackupEngine.decode(archive(["futureKey": "ignored", "monitorCPU": 70]))
        precondition(unknown.count == 1)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await ForkSettingsBackupService.save(data, folder: folder, day: 1)
        try await ForkSettingsBackupService.save(Data(), folder: folder, day: 1)
        let saved = try Data(contentsOf: folder.appendingPathComponent("settings-1.plist"))
        precondition(saved == data)
        print("PASS: round-trip, unknown keys, capability exclusion, corrupt input, daily preservation")
    }

    static func archive(_ values: [String: Any], version: Int = 1) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: [
            "format": version, "created": Date(timeIntervalSince1970: 0), "preferences": values,
        ], format: .binary, options: 0)
    }
}
