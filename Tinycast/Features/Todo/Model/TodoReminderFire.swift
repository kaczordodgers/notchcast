import Foundation

struct TodoReminderFire: Equatable, Sendable {
    let checkedAt: Date
    let due: [TodoReminderSchedule.Entry]
    let missed: [TodoReminderSchedule.Entry]

    var isEmpty: Bool { due.isEmpty && missed.isEmpty }
}
