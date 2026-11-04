import Foundation

@MainActor
final class BlockedDialogModule: NotchcastModule {
    typealias Transport = @MainActor (MachLinkMessage) async throws -> MachLinkMessage
    private let transport: Transport
    private let enabled: @MainActor () -> Bool
    private let present: @MainActor (String) -> Void
    private let now: @MainActor () -> Date
    private var engine = BlockedDialogEngine()
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private(set) var isRunning = false
    private(set) var failed = false

    init(transport: @escaping Transport, enabled: @escaping @MainActor () -> Bool,
         now: @escaping @MainActor () -> Date = Date.init,
         present: @escaping @MainActor (String) -> Void) {
        self.transport = transport
        self.enabled = enabled
        self.now = now
        self.present = present
    }

    isolated deinit { operation?.cancel() }

    func start() { isRunning = true }

    func stop() {
        isRunning = false
        generation = UUID()
        operation?.cancel()
        operation = nil
        engine = BlockedDialogEngine()
        failed = false
    }

    func check() {
        guard isRunning, enabled(), operation == nil else { return }
        let token = generation
        operation = Task { [weak self] in
            guard let self else { return }
            defer { if generation == token { operation = nil } }
            do {
                let request = try MachLinkMessage(method: "dialogs", value: true)
                let response = try await transport(request)
                try Task.checkCancellation()
                guard generation == token, isRunning, enabled() else { return }
                guard response.id == request.id, response.method == request.method else {
                    throw MachLinkMessage.Failure.invalidMessage
                }
                let windows = try response.value(as: [BlockedDialogWindow].self)
                failed = false
                if let window = engine.evaluate(windows, now: now()) { present(window.owner) }
            } catch {
                guard !Task.isCancelled, generation == token, isRunning, enabled() else { return }
                failed = true
            }
        }
    }

    func waitUntilIdle() async { await operation?.value }
}
