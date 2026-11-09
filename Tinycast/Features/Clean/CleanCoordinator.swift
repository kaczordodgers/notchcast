import Foundation
import Observation

@MainActor @Observable
final class CleanCoordinator {
    struct Item: Identifiable, Sendable {
        let id: URL
        let size: Int64?
        var reportOnly = false
        var detail: String?
    }

    struct Review: Sendable {
        let items: [Item]
        let apply: @Sendable ([URL]) async throws -> Void
    }

    struct Transport: Sendable {
        let scan: @Sendable (NotchcastFeature, [URL]) async throws -> Review
    }

    static let features: [NotchcastFeature] = [
        .cleanJunk, .cleanHistory, .cleanAIData, .cleanDisk, .cleanPurge, .cleanOptimize, .cleanSystem
    ]

    private(set) var reviews: [NotchcastFeature: Review] = [:]
    private(set) var busy: Set<NotchcastFeature> = []
    var selection: [NotchcastFeature: Set<URL>] = [:]
    private var enabled: Set<NotchcastFeature> = []
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var identities: [NotchcastFeature: UUID] = [:]
    @ObservationIgnored private var listeners: [NotchcastFeature: () -> Void] = [:]
    @ObservationIgnored private let transport: Transport
    @ObservationIgnored private let isOn: (NotchcastFeature) -> Bool
    @ObservationIgnored private let listen: (NotchcastFeature) -> (() -> Void)
    @ObservationIgnored private let question: @MainActor (NotchcastFeature, Int, Int64?) async -> Bool
    @ObservationIgnored private let optimizeQuestion: @MainActor (CleanOptimizeTask) async -> Bool
    @ObservationIgnored private let report: (Error) -> Void

    init(transport: Transport, isOn: @escaping (NotchcastFeature) -> Bool,
         listen: @escaping (NotchcastFeature) -> (() -> Void) = { _ in {} },
         question: @escaping @MainActor (NotchcastFeature, Int, Int64?) async -> Bool,
         optimizeQuestion: @escaping @MainActor (CleanOptimizeTask) async -> Bool,
         report: @escaping (Error) -> Void) {
        self.transport = transport
        self.isOn = isOn
        self.listen = listen
        self.question = question
        self.optimizeQuestion = optimizeQuestion
        self.report = report
    }

    var rootAvailable: Bool { helperCurrent }

    var helperCurrent = true

    func setEnabled(_ feature: NotchcastFeature, _ value: Bool) {
        if value {
            if enabled.insert(feature).inserted { listeners[feature] = listen(feature) }
        } else {
            enabled.remove(feature)
            if let identity = identities[feature] { tasks[identity]?.cancel() }
            identities.removeValue(forKey: feature)
            listeners.removeValue(forKey: feature)?()
            reviews.removeValue(forKey: feature)
            selection.removeValue(forKey: feature)
            busy.remove(feature)
        }
    }

    func stop() {
        for feature in Self.features { setEnabled(feature, false) }
    }

    func scan(_ feature: NotchcastFeature, roots: [URL] = []) {
        guard feature != .cleanOptimize, available(feature), !busy.contains(feature),
              ![.cleanDisk, .cleanPurge].contains(feature) || !roots.isEmpty else { return }
        let identity = begin(feature)
        reviews.removeValue(forKey: feature)
        selection.removeValue(forKey: feature)
        let scan = transport.scan
        tasks[identity] = Task { [weak self] in
            defer { self?.tasks.removeValue(forKey: identity) }
            do {
                let review = try await scan(feature, roots)
                guard let self, current(feature, identity) else { return }
                reviews[feature] = review
                finish(feature, identity)
            } catch {
                self?.failed(error, feature, identity)
            }
        }
    }

    func apply(_ feature: NotchcastFeature) {
        guard feature != .cleanOptimize, available(feature), !busy.contains(feature),
              let review = reviews[feature] else { return }
        let selected = selection[feature] ?? []
        let candidates = review.items.filter { selected.contains($0.id) && !$0.reportOnly }
        let items = feature == .cleanDisk ? candidates.filter { item in
            !candidates.contains { item.id.path.hasPrefix($0.id.path + "/") }
        } : candidates
        guard !items.isEmpty else { return }
        let size = items.contains { $0.size == nil } ? nil : items.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        let identity = begin(feature)
        tasks[identity] = Task { [weak self] in
            defer { self?.tasks.removeValue(forKey: identity) }
            guard let self else { return }
            guard await question(feature, items.count, size), current(feature, identity) else {
                finish(feature, identity)
                return
            }
            do {
                try await review.apply(items.map(\.id))
                guard current(feature, identity) else { return }
                reviews.removeValue(forKey: feature)
                selection.removeValue(forKey: feature)
                finish(feature, identity)
            } catch {
                failed(error, feature, identity)
            }
        }
    }

    func waitUntilIdle() async {
        let pending = Array(tasks.values)
        for task in pending { await task.value }
    }

    func optimize(_ task: CleanOptimizeTask) {
        let feature = NotchcastFeature.cleanOptimize
        guard available(feature), !busy.contains(feature) else { return }
        let identity = begin(feature)
        let scan = transport.scan
        tasks[identity] = Task { [weak self] in
            defer { self?.tasks.removeValue(forKey: identity) }
            do {
                let review = try await scan(feature, [])
                guard let self, current(feature, identity) else { return }
                guard let item = review.items.first(where: { $0.id.lastPathComponent == task.rawValue }) else {
                    finish(feature, identity)
                    return
                }
                guard await optimizeQuestion(task), current(feature, identity) else {
                    finish(feature, identity)
                    return
                }
                try await review.apply([item.id])
                guard current(feature, identity) else { return }
                finish(feature, identity)
            } catch {
                self?.failed(error, feature, identity)
            }
        }
    }

    private func available(_ feature: NotchcastFeature) -> Bool {
        enabled.contains(feature) && isOn(feature) && (feature != .cleanSystem || rootAvailable)
    }

    private func begin(_ feature: NotchcastFeature) -> UUID {
        let identity = UUID()
        identities[feature] = identity
        busy.insert(feature)
        return identity
    }

    private func current(_ feature: NotchcastFeature, _ identity: UUID) -> Bool {
        !Task.isCancelled && available(feature) && identities[feature] == identity
    }

    private func finish(_ feature: NotchcastFeature, _ identity: UUID) {
        guard identities[feature] == identity else { return }
        identities.removeValue(forKey: feature)
        busy.remove(feature)
    }

    private func failed(_ error: Error, _ feature: NotchcastFeature, _ identity: UUID) {
        let shouldReport = current(feature, identity) && !(error is CancellationError)
        finish(feature, identity)
        if shouldReport { report(error) }
    }
}
