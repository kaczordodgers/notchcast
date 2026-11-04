import Foundation

protocol CleanAIDataGitReader: Sendable {
    func inspect(_ path: URL) async throws -> CleanAIDataGitState?
}

struct CleanAIDataGitState: Sendable {
    let linked: Bool
    let locked: Bool
    let dirty: Bool
    let unpushed: Bool
    let mergedIntoMain: Bool
    let hiddenIndexFlags: Bool
    let submodules: Bool
    let operationInProgress: Bool
    let idle: Bool

    var eligible: Bool {
        linked && !locked && !dirty && !unpushed && mergedIntoMain && !hiddenIndexFlags
            && !submodules && !operationInProgress && idle
    }
}
