import Foundation

enum TodoFilterEngine {
    static func evaluate<Subject: TodoFilterSubject>(
        _ source: String,
        subjects: [Subject],
        now: Date,
        calendar: Calendar,
        projectNames: [String]? = nil,
        labelNames: [String]? = nil,
        sectionNames: [String]? = nil,
        dateResolver: (String) -> Date?
    ) throws(TodoFilterError) -> [[Subject]] {
        let query = try TodoFilterParser.parse(
            source, projectNames: projectNames, labelNames: labelNames,
            sectionNames: sectionNames, dateResolver: dateResolver)
        return evaluate(query, subjects: subjects, now: now, calendar: calendar)
    }

    static func evaluate<Subject: TodoFilterSubject>(
        _ query: TodoFilterQuery, subjects: [Subject], now: Date, calendar: Calendar
    ) -> [[Subject]] {
        let context = Context(now: now, calendar: calendar, today: calendar.startOfDay(for: now))
        return query.lists.map { expression in
            subjects.filter { !$0.isCompleted && context.matches(expression, subject: $0) }
        }
    }

    private struct Context {
        let now: Date
        let calendar: Calendar
        let today: Date

        func matches(_ expression: TodoFilterQuery.Expression, subject: some TodoFilterSubject) -> Bool {
            switch expression {
            case .operand(let operand): matches(operand, subject: subject)
            case .not(let expression): !matches(expression, subject: subject)
            case .and(let left, let right): matches(left, subject: subject) && matches(right, subject: subject)
            case .or(let left, let right): matches(left, subject: subject) || matches(right, subject: subject)
            }
        }

        func matches(_ operand: TodoFilterQuery.Operand, subject: some TodoFilterSubject) -> Bool {
            switch operand {
            case .all: return true
            case .noDate: return subject.dueDate == nil
            case .noLabels: return subject.labels.isEmpty
            case .recurring: return subject.isRecurring
            case .subtask: return subject.isSubtask
            case .priority(let priority): return subject.priority == priority
            case .project(let name, let includingSubprojects):
                return subject.projectName?.compare(name, options: .caseInsensitive) == .orderedSame
                    || (includingSubprojects && subject.projectPath.contains {
                        $0.compare(name, options: .caseInsensitive) == .orderedSame
                    })
            case .section(let name): return subject.sectionName?.compare(name, options: .caseInsensitive) == .orderedSame
            case .label(let name):
                return subject.labels.contains { $0.compare(name, options: .caseInsensitive) == .orderedSame }
            case .search(let text): return subject.title.range(of: text, options: .caseInsensitive) != nil
            default: break
            }
            guard let dueDate = subject.dueDate else { return false }
            let dueDay = calendar.startOfDay(for: dueDate)
            switch operand {
            case .today: return dueDay == today
            case .tomorrow: return dueDay == calendar.date(byAdding: .day, value: 1, to: today)
            case .overdue: return subject.hasTime ? dueDate < now : dueDay < today
            case .dueBefore(let date): return dueDay < calendar.startOfDay(for: date)
            case .dueAfter(let date): return dueDay > calendar.startOfDay(for: date)
            case .days(let count):
                guard let days = calendar.dateComponents([.day], from: today, to: dueDay).day else { return false }
                return days >= 0 && days < count
            default: return false
            }
        }
    }
}
