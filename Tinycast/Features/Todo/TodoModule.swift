import Foundation
import Observation
import OSLog

@MainActor @Observable
final class TodoModule: NotchcastModule {
    private(set) var store: TodoStore?
    private(set) var islandFeed: TodoIslandFeed?
    var islandSnapshot: TodoIslandSnapshot? { islandFeed?.snapshot }
    @ObservationIgnored private let islandEnabled: () -> Bool
    let directory: URL
    @ObservationIgnored let showFailure: (String) -> Void
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored var storeDidOpen: ((TodoStore) -> Void)?
    @ObservationIgnored var storeWillClose: (() -> Void)?

    init(directory: URL, islandEnabled: @escaping () -> Bool = { false }, showFailure: @escaping (String) -> Void) {
        self.directory = directory
        self.islandEnabled = islandEnabled
        self.showFailure = showFailure
    }

    deinit { loading?.cancel() }

    func start() {
        guard operationID == nil else { return }
        let id = UUID()
        operationID = id
        trackIsland(id)
        let directory = directory
        loading = Task { [weak self] in
            do {
                let store = try await TodoStore.open(directory: directory)
                guard !Task.isCancelled, let self, self.operationID == id else {
                    try store.close()
                    return
                }
                self.store = store
                self.storeDidOpen?(store)
                self.loading = nil
                if !store.loadWarnings.isEmpty {
                    self.showFailure(String(localized: "The last task change was interrupted and could not be restored.", table: "Notchcast"))
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, let self, self.operationID == id else { return }
                Logger(subsystem: NotchcastIdentity.releaseFallbackSubsystem, category: "Todo")
                    .error("Task store failed to open: \(error)")
                self.loading = nil
                self.showFailure(String(localized: "The task store could not be opened.", table: "Notchcast"))
            }
        }
    }

    func stop() {
        storeWillClose?()
        islandFeed?.stop()
        islandFeed = nil
        operationID = nil
        loading?.cancel()
        loading = nil
        do { try store?.close() } catch {
            Logger(subsystem: NotchcastIdentity.releaseFallbackSubsystem, category: "Todo")
                .error("Task store failed to close: \(error)")
            showFailure(String(localized: "The task store could not be closed.", table: "Notchcast"))
        }
        store = nil
    }

    private func trackIsland(_ id: UUID) {
        guard operationID == id else { return }
        let enabled = withObservationTracking {
            islandEnabled() && store?.isClosed == false
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.trackIsland(id) }
        }
        if enabled, let store {
            guard islandFeed == nil else { return }
            let feed = TodoIslandFeed(store: store, fileURL: directory.appending(path: "island.json"),
                                      calendar: .current, now: { Date() })
            islandFeed = feed
            feed.start()
        } else {
            islandFeed?.stop()
            islandFeed = nil
            // Switched off: drop the last snapshot so task titles do not linger on disk.
            if !islandEnabled() { try? FileManager.default.removeItem(at: directory.appending(path: "island.json")) }
        }
    }
}
