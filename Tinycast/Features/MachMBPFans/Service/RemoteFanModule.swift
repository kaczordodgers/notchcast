import Foundation
import Observation

@MainActor
@Observable
final class RemoteFanModule: NotchcastModule {
    static let method = "mbp-fans"
    private(set) var report: RemoteFanReport?
    private(set) var isRunning = false
    private var operation: UUID?
    private let transport: any RemoteFanTransport

    init(transport: any RemoteFanTransport) { self.transport = transport }

    func start() { isRunning = true }

    func stop() {
        isRunning = false
        operation = nil
        report = nil
    }

    func run(_ request: RemoteFanRequest) async throws -> RemoteFanReport {
        guard isRunning else { throw RemoteFanReport.Failure.unavailable }
        guard operation == nil else { throw RemoteFanReport.Failure.busy }
        let id = UUID()
        operation = id
        defer { if operation == id { operation = nil } }
        let message = try MachLinkMessage(id: id, method: Self.method, value: request)
        let response = try await transport.exchange(message)
        try Task.checkCancellation()
        guard isRunning, operation == id else { throw CancellationError() }
        guard response.version == 1, response.id == id, response.method == Self.method else {
            throw MachLinkMessage.Failure.invalidMessage
        }
        _ = try response.encoded()
        let value = try response.value(as: RemoteFanReport.self)
        try value.validate(for: request)
        report = value
        return value
    }
}
