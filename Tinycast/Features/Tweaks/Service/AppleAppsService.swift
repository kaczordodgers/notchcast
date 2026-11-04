import Foundation
import CoreFoundation

nonisolated struct AppleAppsService: Sendable {
    enum Failure: Error { case missingInode }

    func readDock() throws -> Data {
        guard let value = CFPreferencesCopyValue("persistent-apps" as CFString, "com.apple.dock" as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw AppleAppsPolicy.Failure.invalidDockData
        }
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        _ = try AppleAppsPolicy.dockPlan(previous: data)
        return data
    }

    func writeDock(_ data: Data) throws {
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard value is [[String: Any]] else { throw AppleAppsPolicy.Failure.invalidDockData }
        CFPreferencesSetValue("persistent-apps" as CFString, value as CFPropertyList,
            "com.apple.dock" as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize("com.apple.dock" as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { throw CocoaError(.fileWriteUnknown) }
    }

    func musicLabel(app: URL) throws -> String {
        func inode(_ url: URL) throws -> UInt64 {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let number = attributes[.systemFileNumber] as? NSNumber else { throw Failure.missingInode }
            return number.uint64Value
        }
        return try AppleAppsPolicy.musicLabel(bundleInode: inode(app),
                                              executableInode: inode(app.appendingPathComponent("Contents/MacOS/Music")))
    }
}
