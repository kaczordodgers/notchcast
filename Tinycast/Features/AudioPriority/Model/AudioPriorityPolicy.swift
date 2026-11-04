// Adapted from Vorssaint (GPL-3.0-or-later)
import Foundation

enum AudioPriorityPolicy {
    static func target(ranking: AudioPriorityRanking, connected: Set<String>,
                       current: String?) -> String? {
        guard ranking.enabled,
              let wanted = ranking.uids.first(where: connected.contains),
              wanted != current else { return nil }
        return wanted
    }
}
