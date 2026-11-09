import Foundation

@MainActor
final class RemoteScreenCoordinator {
    typealias Transport = @MainActor (MachLinkMessage) async throws -> MachLinkMessage
    typealias Open = @MainActor (URL, RemoteScreenState.Client) async throws -> Void
    private(set) var state: RemoteScreenState = .disabled
    private(set) var usedFallback = false
    private let transport: Transport
    private let open: Open
    private var operationID: UUID?

    init(transport: @escaping Transport, open: @escaping Open) {
        self.transport = transport
        self.open = open
    }

    func start() { if state == .disabled { state = .idle } }

    func stop() {
        operationID = nil
        state = .disabled
        usedFallback = false
    }

    func show(_ request: RemoteScreenRequest, preferredClientInstalled: Bool) async throws {
        guard state != .disabled else { throw RemoteScreenRequest.Failure.unavailable }
        _ = try request.validatedURL()
        let message = try MachLinkMessage(method: "remote-screen-availability", value: true)
        let operation = RemoteScreenState.checking(message.id)
        operationID = message.id
        state = operation
        usedFallback = false
        do {
            try Task.checkCancellation()
            let response = try await transport(message)
            try Task.checkCancellation()
            guard operationID == message.id else { throw CancellationError() }
            guard response.id == message.id, response.method == message.method else {
                throw RemoteScreenRequest.Failure.invalidResponse
            }
            let availability = try response.value(as: RemoteScreenState.Availability.self)
            guard availability.peerEnabled != false else { throw RemoteScreenRequest.Failure.peerDisabled }
            guard availability.screenSharingEnabled else { throw RemoteScreenRequest.Failure.sharingDisabled }
            let url = try RemoteScreenRequest(host: availability.host ?? request.host).validatedURL()
            let client: RemoteScreenState.Client = preferredClientInstalled ? .preferred : .apple
            usedFallback = client == .apple
            state = .opening
            try await open(url, client)
            try Task.checkCancellation()
            guard operationID == message.id else { throw CancellationError() }
            state = .opened
        } catch {
            if operationID == message.id { state = .failed }
            throw error
        }
    }

    static func peerResponse(
        to request: MachLinkMessage, enabled: () -> Bool,
        address: () async throws -> RemoteScreenState.Availability
    ) async throws -> MachLinkMessage {
        _ = try request.value(as: Bool.self)
        let off = RemoteScreenState.Availability(screenSharingEnabled: false, peerEnabled: false)
        let current = try await enabled() ? address() : off
        try Task.checkCancellation()
        return try MachLinkMessage(id: request.id, method: request.method, value: enabled() ? current : off)
    }
}
