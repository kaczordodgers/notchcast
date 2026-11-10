import Foundation

nonisolated enum AppleAppsPolicy {
    enum Restriction: String, CaseIterable, Sendable {
        case gameCenter = "allowGameCenter"
        case iPhoneMirroring = "allowiPhoneMirroring"
        case musicService = "allowMusicService"
        case bookstore = "allowBookstore"
    }

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
}
