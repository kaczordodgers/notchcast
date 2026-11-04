import Foundation

struct TodoAgentClaim: Codable, Equatable, Sendable {
    let agent: String
    let claimedAt: Date
    var lastActivityAt: Date
    let previousSectionID: String?
    let claimSectionID: String?
}

enum TodoAgentRequest: Codable, Equatable, Sendable {
    case list(query: String?, sectionID: String?)
    case claim(taskID: String, agent: String)
    case comment(taskID: String, agent: String, text: String)
    case move(taskID: String, agent: String, sectionID: String)
    case complete(taskID: String, agent: String)
    case release(taskID: String, agent: String)
    case releaseExpired
}

enum TodoAgentResponse: Codable, Equatable, Sendable {
    case tasks([TodoTask])
    case task(TodoTask)
    case released([String])
}

enum TodoAgentError: Error, Codable, Equatable, Sendable {
    case unknownTask(String)
    case unknownSection(String)
    case invalidAgent
    case invalidTimeout
    case invalidClock
    case invalidFilter(characterRange: Range<Int>)
    case inProgressSectionRequired(projectID: String?)
    case ambiguousInProgressSection(projectID: String?)
    case alreadyCompleted(String)
    case claimedBy(String)
    case invalidCommand
    case unsupportedRecurrence
}

struct TodoAgentPlan: Sendable {
    let command: TodoCommand
    let response: TodoAgentResponse
}

enum TodoAgentAPI {
    static func plan(_ request: TodoAgentRequest, state: TodoState, now: Date, calendar: Calendar,
                     staleAfterMinutes: Int, makeID: () -> String) throws(TodoAgentError) -> TodoAgentPlan {
        guard staleAfterMinutes > 0 else { throw .invalidTimeout }
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw .invalidClock }
        var working = state
        var commands: [TodoCommand] = []
        let expired = state.tasks.values.filter { task in
            guard let claim = task.claim else { return false }
            let lastComment = task.comments.map(\.createdAt).max() ?? claim.lastActivityAt
            return now.timeIntervalSince(max(lastComment, claim.lastActivityAt)) >= Double(staleAfterMinutes) * 60
        }.sorted { $0.id < $1.id }
        for task in expired {
            try apply(release(task, state: working), state: &working, commands: &commands)
        }
        let response: TodoAgentResponse
        switch request {
        case .list(let query, let sectionID):
            if let sectionID, working.sections[sectionID] == nil { throw .unknownSection(sectionID) }
            var tasks = working.tasks.values.filter { $0.completedAt == nil && (sectionID == nil || $0.sectionID == sectionID) }
                .sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
            if let query {
                let subjects = tasks.map { Subject(task: $0, state: working) }
                do {
                    let lists = try TodoFilterEngine.evaluate(query, subjects: subjects, now: now, calendar: calendar,
                        projectNames: working.projects.values.map(\.name), labelNames: working.labels.values.map(\.name),
                        sectionNames: working.sections.values.map(\.name), dateResolver: { text in
                            TodoDateParser.parse(text, now: now, calendar: calendar, timeZone: calendar.timeZone,
                                                 preferredLanguage: .english)?.date
                        })
                    var seen: Set<String> = []
                    tasks = lists.flatMap { $0 }.map(\.task).filter { seen.insert($0.id).inserted }
                } catch { throw .invalidFilter(characterRange: error.characterRange) }
            }
            response = .tasks(tasks)
        case .releaseExpired:
            response = .released(expired.map(\.id))
        default:
            response = try mutate(request, state: &working, commands: &commands, now: now, calendar: calendar, makeID: makeID)
        }
        return TodoAgentPlan(command: .batch(commands), response: response)
    }

    private static func mutate(_ request: TodoAgentRequest, state: inout TodoState, commands: inout [TodoCommand],
                               now: Date, calendar: Calendar, makeID: () -> String) throws(TodoAgentError) -> TodoAgentResponse {
        let taskID: String
        let agent: String
        switch request {
        case .claim(let id, let name), .complete(let id, let name), .release(let id, let name),
             .comment(let id, let name, _), .move(let id, let name, _):
            taskID = id
            agent = name.trimmingCharacters(in: .whitespacesAndNewlines)
        case .list, .releaseExpired: throw .invalidCommand
        }
        guard !agent.isEmpty, !agent.contains(where: { $0.isNewline || $0.isASCII && $0.asciiValue == 0 }) else {
            throw .invalidAgent
        }
        guard var task = state.tasks[taskID] else { throw .unknownTask(taskID) }
        if let claim = task.claim, claim.agent != agent { throw .claimedBy(claim.agent) }
        if task.completedAt != nil { throw .alreadyCompleted(taskID) }
        let activityAt = max(task.claim?.lastActivityAt ?? now, now)
        switch request {
        case .claim:
            guard task.claim == nil else { return .task(task) }
            var claimSectionID: String?
            if task.parentID == nil {
                let sections = state.sections.values.filter { $0.projectID == task.projectID && $0.name == "In progress" }
                guard !sections.isEmpty else { throw .inProgressSectionRequired(projectID: task.projectID) }
                guard sections.count == 1, let section = sections.first else {
                    throw .ambiguousInProgressSection(projectID: task.projectID)
                }
                claimSectionID = section.id
            }
            task.claim = TodoAgentClaim(agent: agent, claimedAt: now, lastActivityAt: now,
                                        previousSectionID: task.sectionID, claimSectionID: claimSectionID)
            try apply(.updateTask(task), state: &state, commands: &commands)
            if let claimSectionID {
                try apply(.moveTask(id: taskID, projectID: task.projectID, sectionID: claimSectionID, parentID: nil),
                          state: &state, commands: &commands)
            }
            let comment = TodoComment(id: makeID(), text: "claimed by \(agent)", createdAt: now)
            try apply(.addComment(taskID: taskID, comment: comment),
                      state: &state, commands: &commands)
        case .comment(_, _, let text):
            task.claim?.lastActivityAt = activityAt
            try apply(.updateTask(task), state: &state, commands: &commands)
            try apply(.addComment(taskID: taskID, comment: TodoComment(id: makeID(), text: text, createdAt: now)),
                      state: &state, commands: &commands)
        case .move(_, _, let sectionID):
            guard let section = state.sections[sectionID] else { throw .unknownSection(sectionID) }
            task.claim?.lastActivityAt = activityAt
            try apply(.updateTask(task), state: &state, commands: &commands)
            try apply(.moveTask(id: taskID, projectID: section.projectID, sectionID: sectionID, parentID: nil),
                      state: &state, commands: &commands)
        case .complete:
            task.claim = nil
            try apply(.updateTask(task), state: &state, commands: &commands)
            let command: TodoCommand
            do { command = try TodoCompletion.command(id: taskID, state: state, now: now, calendar: calendar) } catch {
                throw .unsupportedRecurrence
            }
            try apply(command, state: &state, commands: &commands)
        case .release:
            guard task.claim != nil else { return .task(task) }
            try apply(release(task, state: state), state: &state, commands: &commands)
        case .list, .releaseExpired: throw .invalidCommand
        }
        guard let result = state.tasks[taskID] else { throw .unknownTask(taskID) }
        return .task(result)
    }

    private static func release(_ task: TodoTask, state: TodoState) -> TodoCommand {
        var updated = task
        let previous = task.claim?.previousSectionID
        updated.claim = nil
        guard let claimSectionID = task.claim?.claimSectionID, task.sectionID == claimSectionID else {
            return .updateTask(updated)
        }
        let sectionID = previous.flatMap { state.sections[$0]?.projectID == task.projectID ? $0 : nil }
        return .batch([.updateTask(updated), .moveTask(id: task.id, projectID: task.projectID,
                                                     sectionID: sectionID, parentID: task.parentID)])
    }

    private static func apply(_ command: TodoCommand, state: inout TodoState,
                              commands: inout [TodoCommand]) throws(TodoAgentError) {
        do { try state.apply(command) } catch { throw .invalidCommand }
        commands.append(command)
    }

    private struct Subject: TodoFilterSubject {
        let task: TodoTask
        let state: TodoState
        var title: String { task.title }
        var projectName: String? { task.projectID.flatMap { state.projects[$0]?.name } }
        var projectPath: [String] { projectName.map { [$0] } ?? [] }
        var sectionName: String? { task.sectionID.flatMap { state.sections[$0]?.name } }
        var labels: [String] { task.labels.compactMap { state.labels[$0]?.name } }
        var priority: Int { task.priority }
        var dueDate: Date? { task.due?.date }
        var hasTime: Bool { task.due?.isAllDay == false }
        var isRecurring: Bool { task.due?.recurrenceRule != nil }
        var isSubtask: Bool { task.parentID != nil }
        var isCompleted: Bool { task.completedAt != nil }
    }
}
