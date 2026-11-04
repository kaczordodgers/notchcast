import Foundation
import Observation

@MainActor @Observable
final class T3ThreadsModule: NotchcastModule {
    private(set) var threads: [T3Thread] = []
    private(set) var error: (any Error)?
    private(set) var isRunning = false
    @ObservationIgnored private var demand: Set<String> = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let source: T3ThreadSource
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let clock: () -> Date

    init(source: T3ThreadSource = .init(), interval: Duration = .seconds(5),
         clock: @escaping () -> Date = Date.init) {
        self.source = source
        self.interval = interval
        self.clock = clock
    }

    var activeThreads: [T3Thread] {
        threads.filter { [.starting, .running, .waiting_for_approval, .waiting_for_input].contains($0.phase) }
    }

    var pendingThreads: [T3Thread] { threads.filter { ($0.pendingRequestCount ?? 0) > 0 } }

    var recentlyFinished: [T3Thread] {
        let now = clock()
        return threads.filter {
            guard [.completed, .failed].contains($0.phase), let date = $0.updatedDate else { return false }
            return (0...1800).contains(now.timeIntervalSince(date))
        }
    }

    func start() { isRunning = true; updatePolling() }

    func stop() {
        isRunning = false
        cancelPolling()
        threads = []
        error = nil
    }

    func setDemand(_ enabled: Bool, for consumer: String) {
        if enabled { demand.insert(consumer) } else { demand.remove(consumer) }
        updatePolling()
    }

    private func cancelPolling() {
        generation += 1
        task?.cancel()
        task = nil
    }

    private func updatePolling() {
        guard isRunning, !demand.isEmpty else { cancelPolling(); return }
        guard task == nil else { return }
        let identity = generation
        let source = source
        let interval = interval
        task = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let threads = try await source.read()
                    guard let self, self.generation == identity, !Task.isCancelled else { return }
                    self.threads = threads
                    self.error = nil
                } catch {
                    guard let self, self.generation == identity, !Task.isCancelled else { return }
                    self.error = error
                }
                do { try await Task.sleep(for: interval) } catch { return }
            }
        }
    }

    deinit { task?.cancel() }
}
