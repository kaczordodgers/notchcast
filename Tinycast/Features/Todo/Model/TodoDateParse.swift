import Foundation

struct TodoDateParse: Sendable {
    let date: Date
    // Keep the requested wall time even when a DST gap moves the resolved instant forward.
    let time: TodoRecurrenceRule.Time?
    let allDay: Bool
    let recurrence: TodoRecurrenceRule?
    let normalised: String
    let matchedRange: Range<String.Index>
}
