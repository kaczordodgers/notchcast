// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoIsland*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoStore*.swift Tinycast/Features/Todo/TodoModule.swift
// notchcast-sources: Tinycast/Features/Todo/TodoModule+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastHost.swift
import Foundation

enum DialogTone { case danger }
@MainActor final class AppCore {}

@main @MainActor
struct TodoModuleTests {
    static func main() async throws {
        var dangers: [String] = []
        NotchcastHost.current.showMessage = { text, tone in if tone == .danger { dangers.append(text) } }
        precondition(TodoModule.shared == nil)
        let entries = TodoModule.register(AppCore())
        precondition(entries.count == 1 && entries[0].requires == [.tasks] && entries[0].requiresAny.isEmpty)
        precondition(entries[0].module === TodoModule.shared && TodoModule.shared?.directory.lastPathComponent == "Todo")
        TodoModule.shared?.showFailure("failed")
        precondition(dangers == ["failed"])
        print("PASS: registration builds the shared module, one entry, failures reach the host seam")
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
