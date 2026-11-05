// notchcast-sources: Tinycast/Features/Shelf/Model/*.swift Tinycast/Features/Shelf/Service/ShelfReceivedStore*.swift
import Foundation

@main
struct ShelfReceivedTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ShelfReceivedStore(directory: root.appendingPathComponent("received"))
        let downloads = root.appendingPathComponent("downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let empty = try await store.entries()
        precondition(empty.isEmpty)
        _ = try await store.receive(ShelfItem(kind: .text, name: "Text", data: Data("Hello".utf8)))
        _ = try await store.receive(ShelfItem(kind: .file, name: "sample.txt", data: Data("New".utf8)))
        let entries = try await store.entries()
        precondition(entries.count == 2)
        precondition(entries[0].receivedAt >= entries[1].receivedAt)
        let file = entries.first { $0.item.kind == .file }!
        let original = downloads.appendingPathComponent("sample.txt")
        try Data("Original".utf8).write(to: original)
        let saved = try await store.save(file, to: downloads)
        let again = try await store.save(file, to: downloads)
        precondition(saved != original && saved != again)
        let originalData = try Data(contentsOf: original)
        let savedData = try Data(contentsOf: saved)
        precondition(originalData == Data("Original".utf8))
        precondition(savedData == file.item.data)
        try await store.remove(file)
        let remaining = try await store.entries()
        precondition(remaining.count == 1 && remaining[0].item.kind == .text)
        try await store.clear()
        let cleared = try await store.entries()
        precondition(cleared.isEmpty)
        print("Shelf received: ordering, remove, clear and save without overwrite passed")
    }
}
