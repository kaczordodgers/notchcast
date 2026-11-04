import Foundation

@MainActor
final class MediaToolsModule: NotchcastModule {
    private var enabled = false
    private var operation: Task<Void, Never>?
    private var identity: UUID?

    func start() { enabled = true }

    func stop() {
        enabled = false
        cancel()
    }

    func cancel() {
        identity = nil
        operation?.cancel()
        operation = nil
    }

    func process(_ inputs: [URL], tool: MediaToolsRunner.Tool,
                 isCurrent: @MainActor () -> Bool,
                 post: @MainActor (String) -> Void) async throws {
        for input in inputs {
            guard enabled, isCurrent() else { return }
            let output = try await MediaToolsRunner().run(input, tool: tool)
            guard enabled, isCurrent(), !Task.isCancelled else { return }
            post(output.path)
        }
    }

    func run(_ input: URL, tool: MediaToolsRunner.Tool, post: @escaping @MainActor (String) -> Void) {
        guard enabled else { return }
        cancel()
        let id = UUID()
        identity = id
        operation = Task { [weak self] in
            do {
                let output = try await MediaToolsRunner().run(input, tool: tool)
                guard !Task.isCancelled, let self, self.identity == id, self.enabled else { return }
                self.identity = nil
                self.operation = nil
                post(output.path)
            } catch {
                guard !Task.isCancelled, let self, self.identity == id, self.enabled else { return }
                self.identity = nil
                self.operation = nil
                post(String(localized: "Media processing failed."))
            }
        }
    }
}
