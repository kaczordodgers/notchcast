import Foundation

@MainActor
final class MediaToolsModule: NotchcastModule {
    private var enabled = false

    func start() { enabled = true }

    func stop() {
        enabled = false
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

}
