// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoIsland*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoStore*.swift Tinycast/Features/Todo/TodoModule.swift
import Foundation

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@main @MainActor
struct TodoModuleTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var failures: [String] = []
        let module = TodoModule(directory: root, showFailure: { failures.append($0) })
        module.start()
        module.stop()
        module.start()
        for _ in 0..<500 where module.store == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(module.store != nil)
        module.stop()
        precondition(module.store == nil && failures.isEmpty)
        print("Todo module: cancelled open, restart and stop passed")
    }
}
