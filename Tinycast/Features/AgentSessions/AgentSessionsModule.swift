import Foundation
import Observation

@MainActor
@Observable
final class AgentSessionsModule: NotchcastModule {
    private(set) var snapshot = AgentSessionIndex.Snapshot()
    private(set) var pricingReport: AgentPricingEngine.Report?
    private let preferences: NotchcastPreferences
    private let availabilityChanged: () -> Void
    private let price: ([AgentSession], Calendar) -> AgentPricingEngine.Report?
    private var pricingEnabled = false
    private var lifetime = UUID()
    @ObservationIgnored private var index = AgentSessionIndex()
    @ObservationIgnored private var task: Task<Void, Never>?
    private let roots: [AgentSessionIndex.Root]
    private let privateConfigURL: URL
    private var enabled = false
    private var operation = UUID()

    init(roots: [AgentSessionIndex.Root] = AgentSessionIndex.Root.defaults(
        home: FileManager.default.homeDirectoryForCurrentUser),
         preferences: NotchcastPreferences = .shared,
         index: AgentSessionIndex = AgentSessionIndex(),
         privateConfigURL: URL = .homeDirectory.appending(path: ".config/notchcast/private.env"),
         availabilityChanged: @escaping () -> Void = {},
         price: @escaping ([AgentSession], Calendar) -> AgentPricingEngine.Report? = AgentSessionPricing.report) {
        self.roots = roots
        self.preferences = preferences
        self.index = index
        self.privateConfigURL = privateConfigURL
        self.availabilityChanged = availabilityChanged
        self.price = price
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        lifetime = UUID()
        watchPricingSwitch()
        availabilityChanged()
    }

    func stop() {
        enabled = false
        lifetime = UUID()
        pricingEnabled = false
        pricingReport = nil
        availabilityChanged()
        cancel()
        snapshot = .init()
        index = .init(calendar: index.calendar)
    }

    func refresh() {
        guard enabled else { return }
        cancel()
        let identity = operation
        let roots = roots
        let privateConfigURL = privateConfigURL
        let initial = index
        task = Task { [weak self] in
            do {
                let (updated, snapshot) = try await Self.scan(initial, roots: roots, privateConfigURL: privateConfigURL)
                guard let self, !Task.isCancelled, self.enabled, self.operation == identity else { return }
                self.index = updated
                if self.snapshot.sessions != snapshot.sessions || self.snapshot.issues != snapshot.issues {
                    let usageChanged = self.snapshot.sessions != snapshot.sessions
                    self.snapshot = snapshot
                    if usageChanged { self.updatePricing() }
                }
                self.task = nil
            } catch {
                return
            }
        }
    }

    private func cancel() {
        operation = UUID()
        task?.cancel()
        task = nil
    }

    private func updatePricing() {
        pricingReport = enabled && pricingEnabled ? price(snapshot.sessions, index.calendar) : nil
    }

    private func watchPricingSwitch() {
        let identity = lifetime
        let next = withObservationTracking {
            preferences.isOn(.agentPricing)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.enabled, self.lifetime == identity else { return }
                self.watchPricingSwitch()
            }
        }
        guard pricingEnabled != next else { return }
        pricingEnabled = next
        updatePricing()
    }

    func waitUntilIdle() async {
        await task?.value
    }

    @concurrent
    private static func scan(_ index: AgentSessionIndex, roots: [AgentSessionIndex.Root],
                             privateConfigURL: URL) async throws -> (AgentSessionIndex, AgentSessionIndex.Snapshot) {
        var updated = index
        updated.excludedPathComponentPrefixes = try AgentSessionExclusions.load(from: privateConfigURL)
        let snapshot = try updated.refresh(roots: roots)
        return (updated, snapshot)
    }
}
