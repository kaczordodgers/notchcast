import Foundation
import Observation

@MainActor
@Observable
final class AgentThreadsState {
    enum Status: Equatable { case idle, loading, ready, unavailable, failed }
    private(set) var threads: [AgentThread] = []
    private(set) var status = Status.idle
    private let runner: any AgentThreadRunning
    private let projects: any AgentThreadProjectReading
    private let now: @Sendable () -> Date
    private var enabled = false
    private var active = false
    private var operation = UUID()
    @ObservationIgnored private var task: Task<Void, Never>?

    init(runner: any AgentThreadRunning = AgentThreadRunner(),
         projects: any AgentThreadProjectReading = AgentThreadProjects(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.runner = runner
        self.projects = projects
        self.now = now
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        refresh()
    }

    func stop() {
        enabled = false
        cancel()
        threads = []
        status = .idle
    }

    func setActive(_ active: Bool) {
        self.active = active
        if active { refresh() } else { cancel() }
    }

    var refreshMessage: String {
        switch status {
        case .unavailable: String(localized: "T3 CLI not found.")
        case .failed: String(localized: "Could not refresh agent threads.")
        default: String(localized: "\(threads.filter { $0.phase.waiting }.count) waiting agent threads.")
        }
    }

    var waitingMessage: String? {
        switch status {
        case .unavailable, .failed: refreshMessage
        default: threads.contains(where: { $0.phase.waiting }) ? nil : String(localized: "No waiting agent threads.")
        }
    }

    func refresh(completion: (@MainActor (AgentThreadsState) -> Void)? = nil) {
        guard enabled else { return }
        cancel()
        let identity = operation
        status = .loading
        task = Task { [weak self, runner, projects, now] in
            var completion = completion
            repeat {
                do {
                    let projects = try await projects.projects()
                    var rows: [AgentThread] = []
                    var successes = 0
                    var listFailure: any Error = AgentThreadFailure.commandFailed
                    for project in projects {
                        try Task.checkCancellation()
                        do {
                            let data = try await runner.run(arguments:
                                ["thread", "list", "--project", project.id, "--json"])
                            rows += try AgentThreadParser.list(data, project: project.title)
                            successes += 1
                        } catch { listFailure = error }
                    }
                    if !projects.isEmpty && successes == 0 { throw listFailure }
                    for index in rows.indices where rows[index].phase == .starting
                        || rows[index].phase == .running || rows[index].phase.waiting {
                        try Task.checkCancellation()
                        if let detail = try? await runner.run(arguments:
                            ["thread", "show", rows[index].id, "--json"]),
                           let updated = try? AgentThreadParser.show(detail, updating: rows[index]) {
                            rows[index] = updated
                        }
                    }
                    guard let self, !Task.isCancelled, self.enabled, self.operation == identity else { return }
                    self.threads = AgentThreadParser.select(rows, now: now())
                    self.status = .ready
                } catch {
                    guard let self, !Task.isCancelled, self.enabled, self.operation == identity else { return }
                    self.status = (error as? AgentThreadFailure) == .unavailable ? .unavailable : .failed
                }
                if let self { completion?(self) }
                completion = nil
                guard self?.active == true else { return }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            } while !Task.isCancelled
        }
    }

    func waitUntilIdle() async { await task?.value }

    private func cancel() {
        operation = UUID()
        task?.cancel()
        task = nil
        if status == .loading { status = threads.isEmpty ? .idle : .ready }
    }
}
