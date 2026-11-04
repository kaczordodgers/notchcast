import Foundation

@MainActor
enum IslandHomeActivityAdapter {
    static func entries(from center: IslandActivityCenter, now: Date) -> [IslandHomeEntry] {
        var entries = center.activities.map { activity in
            IslandHomeEntry(id: .init(source: "activity", key: activity.id.uuidString),
                            state: activity.kind == .status ? .message : .active,
                            title: activity.title, priority: activity.priority,
                            date: now, progress: activity.progress)
        }
        if let message = center.message {
            entries.append(IslandHomeEntry(id: .init(source: "message", key: message.id.uuidString),
                                           state: message.tone == .danger ? .failure
                                               : message.isProgress ? .active : .message,
                                           title: message.text, date: now))
        }
        return entries
    }
}
