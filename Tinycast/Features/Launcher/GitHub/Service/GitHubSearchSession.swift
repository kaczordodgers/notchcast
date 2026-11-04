import Foundation
import Observation

@MainActor
@Observable
final class GitHubSearchSession {
    enum Scope { case repositories, starred }
    enum State: Equatable {
        case idle, loading, ready
        case failed(GitHubService.Failure)
        case unavailable
    }

    static let debounce: Duration = .milliseconds(700)
    private(set) var results: [GitHubRepository] = []
    private(set) var state: State = .idle
    @ObservationIgnored private let service: GitHubService
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var starredTask: Task<[GitHubRepository], Error>?
    private var revision = 0
    private var starredNames: Set<String> = []

    init(service: GitHubService,
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.service = service
        self.sleep = sleep
    }

    deinit { task?.cancel(); starredTask?.cancel() }

    func search(_ text: String, scope: Scope = .repositories) {
        cancelSearch()
        if scope == .starred, starredTask == nil {
            starredTask = Task { [service] in try await service.starred() }
        }
        let starredTask = starredTask
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let stamp = revision
        state = .loading
        task = Task { [weak self, service, sleep] in
            do {
                if !query.isEmpty { try await sleep(Self.debounce) }
                try Task.checkCancellation()
                var repos: [GitHubRepository]
                switch scope {
                case .repositories: repos = try await service.search(query)
                case .starred: repos = try await starredTask!.value
                }
                try Task.checkCancellation()
                guard let self, self.revision == stamp else { return }
                if scope == .starred { self.starredNames = Set(repos.map(\.id)) }
                repos = repos.map { repo in
                    var repo = repo
                    repo.isStarred = self.starredNames.contains(repo.id)
                    return repo
                }
                if scope == .starred, !query.isEmpty {
                    repos = repos.filter {
                        ($0.fullName + " " + ($0.description ?? "")).localizedCaseInsensitiveContains(query)
                    }
                }
                self.results = repos
                self.state = .ready
            } catch {
                guard !Task.isCancelled, let self, self.revision == stamp else { return }
                self.state = (error as? GitHubService.Failure).map(State.failed) ?? .unavailable
            }
        }
    }

    func cancel() {
        starredTask?.cancel()
        starredTask = nil
        cancelSearch()
    }

    private func cancelSearch() {
        revision &+= 1
        task?.cancel()
        task = nil
        results = []
        state = .idle
    }
}
