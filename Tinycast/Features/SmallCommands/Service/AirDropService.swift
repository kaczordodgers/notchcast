import AppKit

@MainActor
final class AirDropService: NSObject, NSSharingServiceDelegate {
    enum Outcome: Equatable, Sendable {
        case sent(Int)
        case cancelled
        case noSelection
        case unavailable
    }
    enum Failure: Error { case busy, invalidSelection }

    private let selection: @MainActor () async throws -> [URL]
    private let makeService: @MainActor ([URL]) -> NSSharingService?
    private let perform: @MainActor (NSSharingService, [URL]) -> Void
    private let activate: @MainActor () -> Void
    private var service: NSSharingService?
    private var continuation: CheckedContinuation<Outcome, any Error>?
    private var operation: UUID?
    private var count = 0

    init(
        selection: @escaping @MainActor () async throws -> [URL] = {
            try await CopyPathSystemReader.read(.finderSelection).map { URL(filePath: $0) }
        },
        makeService: @escaping @MainActor ([URL]) -> NSSharingService? = { files in
            NSSharingService(named: .sendViaAirDrop).flatMap { $0.canPerform(withItems: files) ? $0 : nil }
        },
        perform: @escaping @MainActor (NSSharingService, [URL]) -> Void = { $0.perform(withItems: $1) },
        activate: @escaping @MainActor () -> Void = { NSApp.activate() }
    ) {
        self.selection = selection
        self.makeService = makeService
        self.perform = perform
        self.activate = activate
    }

    func shareSelection() async throws -> Outcome {
        try Task.checkCancellation()
        guard operation == nil else { throw Failure.busy }
        let id = UUID()
        operation = id
        defer { if operation == id { operation = nil } }
        let files = try await selection()
        try Task.checkCancellation()
        guard operation == id else { throw CancellationError() }
        guard !files.isEmpty else { return .noSelection }
        guard files.allSatisfy(\.isFileURL) else { throw Failure.invalidSelection }
        guard let sharing = makeService(files) else { return .unavailable }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                service = sharing
                count = files.count
                sharing.delegate = self
                activate()
                perform(sharing, files)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.operation == id else { return }
                self.finish(.failure(CancellationError()))
            }
        }
    }

    func stop() {
        operation = nil
        finish(.failure(CancellationError()))
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        guard sharingService === service else { return }
        finish(.success(.sent(count)))
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        guard sharingService === service else { return }
        finish(.success((error as NSError).code == NSUserCancelledError ? .cancelled : .unavailable))
    }

    private func finish(_ result: Result<Outcome, any Error>) {
        let pending = continuation
        continuation = nil
        service?.delegate = nil
        service = nil
        pending?.resume(with: result)
    }
}
