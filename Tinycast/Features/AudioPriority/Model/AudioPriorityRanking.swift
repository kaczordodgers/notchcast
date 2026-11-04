// Adapted from Vorssaint (GPL-3.0-or-later)
import Foundation

struct AudioPriorityRanking: Codable, Equatable, Sendable {
    var enabled = false
    var uids: [String] = []

    mutating func appendUnknown(_ connected: [String]) {
        for uid in connected where !uid.isEmpty && !uids.contains(uid) {
            uids.append(uid)
        }
    }
}
