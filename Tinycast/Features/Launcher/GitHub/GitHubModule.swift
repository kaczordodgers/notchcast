import Foundation

@MainActor
final class GitHubModule: NotchcastModule {
    static let account = UUID(uuidString: "273EF64E-C3CE-4237-994C-E8219B2F471D")!
    let session: GitHubSearchSession
    private(set) var isRunning = false

    init(service: GitHubService = GitHubService(account: account)) {
        session = GitHubSearchSession(service: service)
    }

    func start() { isRunning = true }
    func stop() { isRunning = false; session.cancel() }

    func search(_ query: String, scope: GitHubSearchSession.Scope = .repositories) {
        guard isRunning else { return }
        session.search(query, scope: scope)
    }
}
