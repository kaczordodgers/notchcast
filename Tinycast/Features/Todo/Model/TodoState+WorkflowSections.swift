import Foundation

extension TodoState {
    func workflowSectionsCommand(projectID: String, makeID: () -> String) throws -> TodoCommand? {
        guard projects[projectID] != nil else { throw TodoCommandError.unknownID(.project, projectID) }
        let existing = sections.values.filter { $0.projectID == projectID }
        let names = Set(existing.map { $0.name.lowercased() })
        let missing = Self.workflowSections.filter { !names.contains($0.lowercased()) }
        guard !missing.isEmpty else { return nil }
        let maximum = existing.map(\.order).max() ?? -1
        let (start, overflow) = maximum.addingReportingOverflow(1)
        let canAppend = !overflow && start <= Int.max - (missing.count - 1)
        var commands: [TodoCommand] = []
        if !canAppend {
            let ordered = existing.sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
            commands.append(.reorder(kind: .section, orders: Dictionary(uniqueKeysWithValues:
                ordered.enumerated().map { ($0.element.id, $0.offset) })))
        }
        for (offset, name) in missing.enumerated() {
            let order = (canAppend ? start : existing.count) + offset
            commands.append(.addSection(.init(id: makeID(), name: name, projectID: projectID, order: order)))
        }
        return .batch(commands)
    }
}
