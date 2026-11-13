import Foundation

enum TodoistImportMapper {
    struct ImportReport: Sendable {
        let commands: [TodoCommand]
        let unparsedRecurrences: [String]
        let unparsedDues: [String]
    }

    enum ImportError: Error { case invalidDate(String), invalidReference(String) }

    static func map(_ data: Data, into state: TodoState, includeCompleted: Bool = false,
                    now: Date, calendar: Calendar, timeZone: TimeZone,
                    makeID: () -> String) throws -> ImportReport {
        let export = try JSONDecoder().decode(Export.self, from: data)
        var candidate = state
        var commands: [TodoCommand] = []
        var unparsed: [String] = []
        var unparsedDues: [String] = []
        var projects: [String: String] = [:]
        var sections: [String: String] = [:]
        var labels: [String: String] = [:]
        for project in export.projects ?? [] {
            let ref = "todoist:\(project.id)"
            let existing = candidate.projects.values.first { $0.externalRef == ref }
            let id = existing?.id ?? makeID()
            projects[project.id] = id
            if existing == nil {
                let command = TodoCommand.addProject(TodoProject(id: id, name: project.name,
                    order: project.child_order ?? 0, externalRef: ref))
                try candidate.apply(command)
                commands.append(command)
            }
        }
        for section in export.sections ?? [] {
            guard let project = projects[section.project_id] else {
                throw ImportError.invalidReference(section.id)
            }
            let existing = candidate.sections.values.first { $0.projectID == project && $0.name == section.name }
            let id = existing?.id ?? makeID()
            sections[section.id] = id
            if existing == nil {
                let command = TodoCommand.addSection(TodoSection(id: id, name: section.name,
                    projectID: project, order: section.child_order ?? 0))
                try candidate.apply(command)
                commands.append(command)
            }
        }
        for label in export.labels ?? [] {
            let existing = candidate.labels.values.first { $0.name == label.name }
            let id = existing?.id ?? makeID()
            labels[label.name] = id
            labels[label.id] = id
            if existing == nil {
                let command = TodoCommand.addLabel(TodoLabel(id: id, name: label.name))
                try candidate.apply(command)
                commands.append(command)
            }
        }
        let tasks = export.tasks.filter { includeCompleted || !($0.is_completed ?? false) }
        var taskIDs: [String: String] = [:]
        for task in tasks {
            taskIDs[task.id] = state.tasks.values.first { $0.externalRef == "todoist:\(task.id)" }?.id ?? makeID()
        }
        for source in tasks {
            let ref = "todoist:\(source.id)"
            guard !state.tasks.values.contains(where: { $0.externalRef == ref }) else { continue }
            guard let id = taskIDs[source.id] else { throw ImportError.invalidReference(source.id) }
            var task = TodoTask(id: id, title: source.content)
            task.description = source.description ?? ""
            task.externalRef = ref
            task.priority = source.priority ?? 1
            task.order = source.child_order ?? 0
            task.projectID = try reference(source.project_id, in: projects)
            task.sectionID = try reference(source.section_id, in: sections)
            task.parentID = source.parent_id.flatMap { taskIDs[$0] }
            task.labels = try (source.labels ?? []).map { name in
                if let id = labels[name] ?? candidate.labels.values.first(where: { $0.name == name })?.id {
                    labels[name] = id
                    return id
                }
                // Shared labels are absent from the export's labels array; they arrive by name.
                let label = TodoLabel(id: makeID(), name: name)
                try candidate.apply(.addLabel(label))
                commands.append(.addLabel(label))
                labels[name] = label.id
                return label.id
            }
            if source.is_completed == true { task.completedAt = now }
            if let due = source.due {
                var localCalendar = calendar
                let zone = due.timezone.flatMap(TimeZone.init(identifier:)) ?? timeZone
                localCalendar.timeZone = zone
                let text = due.datetime ?? due.date
                let timed = text.contains("T")
                let date = timed ? timedDate(text, zone: zone) : TodoDateParser.parse(text,
                    now: now, calendar: localCalendar, timeZone: zone, preferredLanguage: .english)?.date
                if let date {
                    let parsed = TodoDateParser.parse(due.string ?? "", now: now, calendar: localCalendar,
                        timeZone: zone, preferredLanguage: .english)
                    let rule = due.is_recurring == true ? parsed?.recurrence?.canonicalString : nil
                    if due.is_recurring == true && rule == nil { unparsed.append(ref) }
                    task.due = TodoTask.Due(date: date,
                        time: !timed ? nil : localCalendar.dateComponents([.hour, .minute], from: date),
                        isAllDay: !timed, recurrenceRule: rule,
                        normalized: rule ?? due.string ?? due.date)
                } else { unparsedDues.append(ref) }
            }
            let comments = (source.comments ?? []) + (source.notes ?? [])
                + (export.comments ?? []).filter { $0.task_id == source.id }
                + (export.notes ?? []).filter { $0.task_id == source.id }
            task.comments = comments.map {
                TodoComment(id: makeID(), text: $0.content,
                    createdAt: $0.posted_at.flatMap { ISO8601DateFormatter().date(from: $0) } ?? now)
            }
            commands.append(.addTask(task))
        }
        var validation = state
        try validation.apply(.batch(commands))
        return ImportReport(commands: commands, unparsedRecurrences: unparsed, unparsedDues: unparsedDues)
    }

    private static func reference(_ id: String?, in values: [String: String]) throws -> String? {
        guard let id else { return nil }
        guard let value = values[id] else { throw ImportError.invalidReference(id) }
        return value
    }

    private static func timedDate(_ text: String, zone: TimeZone) -> Date? {
        if let date = ISO8601DateFormatter().date(from: text) ?? fractionalDate(text) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.isLenient = false
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: text)
    }

    private static func fractionalDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    private struct Export: Decodable {
        var projects: [Project]?
        var sections: [Section]?
        var labels: [Label]?
        var tasks: [Task]
        var comments: [Comment]?
        var notes: [Comment]?
    }
    private struct Project: Decodable { let id: String; let name: String; var child_order: Int? }
    private struct Section: Decodable {
        let id: String
        let name: String
        let project_id: String
        var child_order: Int?
    }
    private struct Label: Decodable { let id: String; let name: String }
    private struct Comment: Decodable {
        let content: String
        var task_id: String?
        var posted_at: String?
    }
    private struct Due: Decodable {
        let date: String
        var datetime: String?
        var string: String?
        var is_recurring: Bool?
        var timezone: String?
    }
    private struct Task: Decodable {
        let id: String
        let content: String
        var description: String?
        var project_id: String?
        var section_id: String?
        var parent_id: String?
        var labels: [String]?
        var priority: Int?
        var due: Due?
        var child_order: Int?
        var is_completed: Bool?
        var comments: [Comment]?
        var notes: [Comment]?
    }
}
