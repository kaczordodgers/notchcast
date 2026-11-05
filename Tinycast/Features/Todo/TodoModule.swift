import Foundation
import Observation
import OSLog

@MainActor @Observable
final class TodoModule: NotchcastModule {
    private(set) var store: TodoStore?
    let directory: URL
    @ObservationIgnored let showFailure: (String) -> Void
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var operationID: UUID?
    @ObservationIgnored var storeDidOpen: ((TodoStore) -> Void)?
    @ObservationIgnored var storeWillClose: (() -> Void)?

    init(directory: URL, showFailure: @escaping (String) -> Void) {
        self.directory = directory
        self.showFailure = showFailure
    }

    deinit { loading?.cancel() }

    func start() {
        guard operationID == nil else { return }
        let id = UUID()
        operationID = id
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
                    self.showFailure(String(localized: "The last task change was interrupted and could not be restored."))
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, let self, self.operationID == id else { return }
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast", category: "Todo")
                    .error("Task store failed to open: \(error)")
                self.loading = nil
                self.showFailure(String(localized: "The task store could not be opened."))
            }
        }
    }

    func stop() {
        storeWillClose?()
        operationID = nil
        loading?.cancel()
        loading = nil
        do { try store?.close() } catch {
            Logger(subsystem: Bundle.main.bundleIdentifier ?? "app.notchcast", category: "Todo")
                .error("Task store failed to close: \(error)")
            showFailure(String(localized: "The task store could not be closed."))
        }
        store = nil
    }
}
