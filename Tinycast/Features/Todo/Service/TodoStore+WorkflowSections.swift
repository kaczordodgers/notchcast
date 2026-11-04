import Foundation

extension TodoStore {
    func applyWorkflowSections(projectID: String) throws {
        guard let command = try state.workflowSectionsCommand(projectID: projectID, makeID: { UUID().uuidString }) else {
            return
        }
        try perform(command)
    }
}
