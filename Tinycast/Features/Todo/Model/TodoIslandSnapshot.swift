import Foundation

struct TodoIslandSnapshot: Codable, Equatable, Sendable {
    enum Attention: String, Codable, Sendable { case none, dueNow, overdue }

    struct Row: Codable, Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let dueTime: Date?
        let priority: Int
        let projectName: String?
    }

    let overdue: [Row]
    let today: [Row]
    let tomorrow: [Row]
    let overflowCount: Int
    let attention: Attention

    init(state: TodoState, now: Date, calendar: Calendar) {
        let start = calendar.startOfDay(for: now)
        let views = TodoViews(state: state, now: now, calendar: calendar)
        let current = views.today().flatMap { $0.tasks.map(\.task) }
        let next = views.upcoming(days: 2).last?.groups.flatMap { $0.tasks.map(\.task) } ?? []
        let past = current.filter { ($0.due?.date ?? start) < start }
        let present = current.filter { ($0.due?.date ?? start) >= start }
        attention = !past.isEmpty ? .overdue : present.contains {
            $0.due.map { !$0.isAllDay && $0.date <= now } ?? false
        } ? .dueNow : .none
        var remaining = 16
        func rows(_ tasks: [TodoTask]) -> [Row] {
            let result = tasks.prefix(remaining).map { task in
                Row(id: task.id, title: task.title,
                    dueTime: task.due.flatMap { $0.isAllDay ? nil : $0.date },
                    priority: task.priority,
                    projectName: task.projectID.flatMap { state.projects[$0]?.name })
            }
            remaining -= result.count
            return result
        }
        overdue = rows(past)
        today = rows(present)
        tomorrow = rows(next)
        overflowCount = max(0, current.count + next.count - 16)
    }
}
