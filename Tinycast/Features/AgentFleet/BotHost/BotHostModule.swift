import Foundation
import Observation

@MainActor
@Observable
final class BotHostModule: NotchcastModule, BotHostClient {
    private(set) var enabled = false
    private(set) var states: [String: BotHostState] = [:]
    private(set) var pendingCounts: [String: Int] = [:]
    var isConfigured: Bool { client != nil }
    private var generation = UUID()
    private var client: (any BotHostClient)?

    init(client: (any BotHostClient)? = nil) { self.client = client }

    func configure(client: any BotHostClient) {
        generation = UUID()
        self.client = client
    }

    func start() { enabled = true }

    func stop() {
        enabled = false
        states = [:]
        pendingCounts = [:]
        generation = UUID()
    }

    private func call<T: Sendable>(
        _ operation: (any BotHostClient) async throws -> T
    ) async throws -> T {
        guard enabled, let client else { throw BotHostTransport.Failure.rejected }
        let identity = generation
        try Task.checkCancellation()
        let result = try await operation(client)
        try Task.checkCancellation()
        guard enabled, generation == identity else { throw CancellationError() }
        return result
    }

    func list() async throws -> [BotHostBot] { try await call { try await $0.list() } }

    func message(botID: String, text: String) async throws -> BotHostState {
        try await call { try await $0.message(botID: botID, text: text) }
    }

    func status(botID: String) async throws -> BotHostState {
        let result = try await call { try await $0.status(botID: botID) }
        states[botID] = result
        return result
    }

    func pending(botID: String) async throws -> [BotHostPending] {
        let result = try await call { try await $0.pending(botID: botID) }
        pendingCounts[botID] = result.count
        return result
    }

    func answer(botID: String, requestID: String, text: String) async throws -> BotHostState {
        try await call { try await $0.answer(botID: botID, requestID: requestID, text: text) }
    }

    func approve(botID: String, requestID: String, optionID: String) async throws -> BotHostState {
        try await call { try await $0.approve(botID: botID, requestID: requestID, optionID: optionID) }
    }
}
