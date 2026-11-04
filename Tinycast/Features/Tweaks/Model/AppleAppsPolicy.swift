import Foundation

nonisolated enum AppleAppsPolicy {
    enum Restriction: String, CaseIterable, Sendable {
        case gameCenter = "allowGameCenter"
        case iPhoneMirroring = "allowiPhoneMirroring"
        case musicService = "allowMusicService"
        case bookstore = "allowBookstore"
    }

    static let removedDockIdentifiers: Set<String> = [
        "com.apple.news", "com.apple.TV", "com.apple.Music", "com.apple.podcasts", "com.apple.iBooksX",
        "com.apple.freeform", "com.apple.Maps", "com.apple.stocks",
        "com.apple.GenerativePlaygroundApp", "com.apple.journal",
    ]

    static func profile(_ restrictions: Set<Restriction>, identifier: String,
                        profileUUID: UUID, payloadUUID: UUID) throws -> Data {
        var payload: [String: Any] = [
            "PayloadType": "com.apple.applicationaccess", "PayloadVersion": 1,
            "PayloadIdentifier": identifier + ".restrictions", "PayloadUUID": payloadUUID.uuidString,
        ]
        for restriction in restrictions { payload[restriction.rawValue] = false }
        return try PropertyListSerialization.data(fromPropertyList: [
            "PayloadType": "Configuration", "PayloadVersion": 1, "PayloadScope": "System",
            "PayloadIdentifier": identifier, "PayloadUUID": profileUUID.uuidString,
            "PayloadContent": [payload],
        ], format: .xml, options: 0)
    }

    static func dockPlan(previous: Data) throws -> DockRemovalPlan {
        guard let tiles = try PropertyListSerialization.propertyList(from: previous, format: nil)
            as? [[String: Any]] else { throw Failure.invalidDockData }
        let filtered = tiles.filter { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let identifier = data["bundle-identifier"] as? String else { return true }
            return !removedDockIdentifiers.contains(identifier)
        }
        return try DockRemovalPlan(previous: previous, replacement: PropertyListSerialization.data(
            fromPropertyList: filtered, format: .xml, options: 0
        ))
    }

    struct DockRemovalPlan: Sendable, Equatable {
        let previous: Data
        let replacement: Data
    }

    enum Failure: Error { case invalidDockData, invalidMusicLabel }

    static func musicLabel(bundleInode: UInt64, executableInode: UInt64) -> String {
        "application.com.apple.Music.\(bundleInode).\(executableInode)"
    }

    static func serviceCommands(musicLabel: String? = nil, userID: UInt32, disabled: Bool)
        throws -> [TypingPreferencePlan.Command] {
        let label = musicLabel ?? "com.apple.rcd"
        if let musicLabel {
            let suffix = musicLabel.dropFirst("application.com.apple.Music.".count)
            let numbers = suffix.split(separator: ".", omittingEmptySubsequences: false)
            guard musicLabel.hasPrefix("application.com.apple.Music."), numbers.count == 2,
                  numbers.allSatisfy({ UInt64($0) != nil }) else { throw Failure.invalidMusicLabel }
        }
        let target = "gui/\(userID)/\(label)"
        let command = TypingPreferencePlan.Command(executable: "/bin/launchctl",
                                                  arguments: [disabled ? "disable" : "enable", target])
        return disabled ? [command, .init(executable: "/bin/launchctl", arguments: ["bootout", target])] : [command]
    }
}
