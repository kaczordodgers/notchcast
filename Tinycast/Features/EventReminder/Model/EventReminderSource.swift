import Foundation

@MainActor
protocol EventReminderSource: AnyObject {
    func reminderEvents(in interval: DateInterval) -> [EventReminderEngine.Event]
}
