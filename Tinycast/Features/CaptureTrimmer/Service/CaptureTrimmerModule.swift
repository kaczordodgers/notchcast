import Foundation
import Observation

@MainActor
@Observable
final class CaptureTrimmerModule: NotchcastModule {
    typealias Writer = @MainActor (URL) throws -> Void
    private(set) var enabled = false
    private(set) var recoverable: [URL] = []
    private(set) var recoveryError: Error?
    private let folder: URL
    private let writer: Writer
    private var generation = UUID()
    private var scan: Task<Void, Never>?
    private var exports: [UUID: Task<URL, Error>] = [:]

    init(workFolder: URL, clipboardWriter: @escaping Writer) {
        folder = workFolder
        writer = clipboardWriter
    }

    func start() {
        guard !enabled else { return }
        enabled = true
        let identity = UUID()
        generation = identity
        recoveryError = nil
        scan = Task { [weak self, folder] in
            do {
                let items = try await CaptureTrimService.recoverable(in: folder)
                try Task.checkCancellation()
                guard let self, self.generation == identity else { return }
                self.recoverable = items
            } catch {
                guard let self, self.generation == identity, !Task.isCancelled else { return }
                self.recoveryError = error
            }
        }
    }

    func stop() {
        enabled = false
        generation = UUID()
        scan?.cancel()
        scan = nil
        for task in exports.values { task.cancel() }
        exports.removeAll()
        recoverable = []
    }

    func save(source: URL, trim: CaptureTrim, destination: URL, copy: Bool = false) async throws -> URL {
        guard enabled else { throw CancellationError() }
        let identity = generation
        let operation = UUID()
        let task = Task { try await CaptureTrimService.save(source: source, trim: trim, destination: destination) }
        exports[operation] = task
        defer { exports[operation] = nil }
        let result = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard enabled, generation == identity else { throw CancellationError() }
        if copy { try writer(result) }
        return result
    }

    isolated deinit {
        scan?.cancel()
        for task in exports.values { task.cancel() }
    }
}
