import Foundation

enum TweaksJournalFailure: LocalizedError, Equatable, Sendable {
    case unreadable
    case entriesDropped

    var errorDescription: String? {
        switch self {
        case .unreadable:
            String(localized: "The tweaks journal could not be read, so tweaks cannot be changed.", table: "Notchcast")
        case .entriesDropped:
            String(localized: "Some entries in the tweaks journal could not be read and were removed.", table: "Notchcast")
        }
    }
}

enum TweaksJournal {
    static func load(_ data: Data?, home: String) -> (plans: [String: TypingPreferencePlan], failure: TweaksJournalFailure?) {
        guard let data else { return ([:], nil) }
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([:], .unreadable)
        }
        var plans: [String: TypingPreferencePlan] = [:]
        for (identifier, entry) in entries {
            guard let encoded = try? JSONSerialization.data(withJSONObject: entry, options: .fragmentsAllowed),
                  let plan = try? JSONDecoder().decode(TypingPreferencePlan.self, from: encoded),
                  plan.permitsJournal(home: home) else { continue }
            plans[identifier] = plan
        }
        if plans.count == entries.count { return (plans, nil) }
        return (plans, plans.isEmpty ? .unreadable : .entriesDropped)
    }
}
