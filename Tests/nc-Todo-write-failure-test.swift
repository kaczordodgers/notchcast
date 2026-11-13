// notchcast-sources: Tinycast/Features/Todo/Model/*.swift
// notchcast-sources: Tinycast/Features/Todo/Service/TodoStore.swift
// notchcast-kit: core
import Foundation

@main @MainActor
struct TodoWriteFailureTests {
    enum Injected: Error { case write }

    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var fail = false
        let store = try await TodoStore.open(directory: directory) { log, data in
            if fail {
                try log.write(contentsOf: data.prefix(8))
                throw Injected.write
            }
            try log.write(contentsOf: data)
        }
        let task = TodoTask(id: UUID().uuidString, title: "Durable")
        try store.perform(.addTask(task))
        let state = store.state
        let logURL = directory.appending(path: "commands.jsonl")
        let bytes = try Data(contentsOf: logURL)
        fail = true
        do {
            try store.perform(.addTask(.init(id: UUID().uuidString, title: "Rejected")))
            preconditionFailure("Injected write failure must escape")
        } catch Injected.write {}
        precondition(store.state == state && store.canUndo)
        let after = try Data(contentsOf: logURL)
        precondition(after == bytes, "Partial append must be truncated")
        fail = false
        try store.undo()
        precondition(store.state.tasks.isEmpty)
        try store.close()
        let reopened = try await TodoStore.open(directory: directory)
        precondition(reopened.state.tasks.isEmpty && reopened.loadWarnings.isEmpty)
        try reopened.close()
        print("PASS: partial write failure preserves state, undo and a replayable log")
    }
}
