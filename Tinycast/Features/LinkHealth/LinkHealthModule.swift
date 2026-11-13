import Foundation
import Observation

@MainActor @Observable
final class LinkHealthModule: NotchcastModule {
    typealias Probe = @MainActor () async throws -> Duration

    private(set) var health = LinkHealthEngine()
    private(set) var isRunning = false
    @ObservationIgnored private let probe: Probe
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let pause: @MainActor () async throws -> Void
    @ObservationIgnored private let post: @MainActor (String) -> Void
    @ObservationIgnored private var polling: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()

    init(probe: @escaping Probe, now: @escaping () -> Date = Date.init,
         pause: @escaping @MainActor () async throws -> Void = { try await Task.sleep(for: .seconds(60)) },
         post: @escaping @MainActor (String) -> Void) {
        self.probe = probe
        self.now = now
        self.pause = pause
        self.post = post
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        let current = generation
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(generation: current)
                do { try await self?.pause() } catch { return }
            }
        }
    }

    func stop() {
        generation = UUID()
        polling?.cancel()
        polling = nil
        isRunning = false
        health = LinkHealthEngine()
    }

    private func refresh(generation current: UUID) async {
        let latency = try? await probe()
        guard !Task.isCancelled, isRunning, generation == current else { return }
        guard let notice = health.consume(latency: latency, at: now()) else { return }
        switch notice {
        case .lost: post(String(localized: "Mac link lost.", table: "Notchcast"))
        case .recovered: post(String(localized: "Mac link restored.", table: "Notchcast"))
        }
    }

    isolated deinit { polling?.cancel() }
}
