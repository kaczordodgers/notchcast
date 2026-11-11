import Foundation

@MainActor
final class MacUpdateService {
    enum State: Equatable, Sendable {
        case running, skipped(String), done(Int), failed(String), cancelled
    }

    struct Progress: Sendable {
        var step: MacUpdateStep
        var state: State
    }

    private let runner: any MacUpdateProcessRunning
    private let appRoot: String
    private let exists: (String) -> Bool
    private let resolve: (String) -> String
    private let locked: () -> Bool
    private let lockTimeout: Duration
    private let locate: @Sendable (String) async -> String?
    private var task: Task<Void, Never>?

    init(runner: any MacUpdateProcessRunning, appRoot: String,
         exists: @escaping (String) -> Bool, resolve: @escaping (String) -> String,
         locked: @escaping () -> Bool, lockTimeout: Duration = .seconds(120),
         locate: @escaping @Sendable (String) async -> String? = { await ExecutableLocator.locate($0)?.path }) {
        self.runner = runner
        self.appRoot = appRoot
        self.exists = exists
        self.resolve = resolve
        self.locked = locked
        self.lockTimeout = lockTimeout
        self.locate = locate
    }

    func run() -> AsyncStream<Progress>? {
        guard task == nil else { return nil }
        let (stream, continuation) = AsyncStream<Progress>.makeStream(bufferingPolicy: .bufferingNewest(32))
        task = Task {
            await perform(continuation)
            task = nil
            continuation.finish()
        }
        return stream
    }

    func cancel() { task?.cancel() }

    func stop() async {
        task?.cancel()
        let deadline = ContinuousClock.now + .seconds(2)
        while task != nil && ContinuousClock.now < deadline {
            await Task.detached { try? await Task.sleep(for: .milliseconds(25)) }.value
        }
    }

    private func perform(_ progress: AsyncStream<Progress>.Continuation) async {
        let tools = await withTaskGroup(of: (String, String?).self) { [locate] group in
            for name in MacUpdatePlan.tools { group.addTask { (name, await locate(name)) } }
            var found: [String: String] = [:]
            for await (name, path) in group { found[name] = path }
            return found
        }
        for step in MacUpdateStep.allCases {
            func emit(_ state: State) { progress.yield(Progress(step: step, state: state)) }
            do {
                try Task.checkCancellation()
                switch MacUpdatePlan.make(step, tools: tools, exists: exists, resolve: resolve) {
                case .skipped(let reason): emit(.skipped(reason))
                case .commands(let commands):
                    emit(.running)
                    var count = 0
                    for command in commands {
                        if command.path.hasSuffix("/brew") {
                            let deadline = ContinuousClock.now + lockTimeout
                            while locked() {
                                guard ContinuousClock.now < deadline else {
                                    emit(.failed("homebrew-lock-timeout"))
                                    return
                                }
                                try await Task.sleep(for: .milliseconds(25))
                            }
                        }
                        let result = try await runner.run(command)
                        try Task.checkCancellation()
                        guard result.status == 0 && !result.timedOut else {
                            emit(.failed(result.timedOut ? "timeout" : String(result.output.suffix(200))))
                            return
                        }
                        let output = String(result.output.suffix(65536))
                        count += output.split(whereSeparator: \.isNewline).reduce(0) { sum, line in
                            guard let match = line.firstMatch(of: /Upgrading (\d+) outdated/) else { return sum }
                            return sum + (Int(match.1) ?? 0)
                        }
                        if command.path.hasSuffix("/brew"), command.arguments.first == "upgrade" {
                            for app in Set(MacUpdatePlan.upgradedApps(output: output, root: appRoot)) {
                                let real = resolve(app)
                                guard real == app, exists("/usr/bin/xattr") else { continue }
                                let cleanup = try await runner.run(MacUpdateCommand(
                                    path: "/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", app],
                                    timeout: .seconds(30)))
                                try Task.checkCancellation()
                                guard cleanup.status == 0 && !cleanup.timedOut else {
                                    emit(.failed("quarantine-cleanup-failed"))
                                    return
                                }
                            }
                        }
                    }
                    emit(.done(count))
                }
            } catch is CancellationError {
                emit(.cancelled)
                return
            } catch {
                emit(.failed(String(describing: error)))
                return
            }
        }
    }
}
