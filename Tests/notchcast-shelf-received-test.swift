// notchcast-sources: Tinycast/Features/Shelf/Model/*.swift Tinycast/Features/Shelf/Service/ShelfReceivedStore*.swift
import Foundation
import Darwin

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
        precondition(getxattr(saved.path, "com.apple.quarantine", nil, 0, 0, 0) > 0)
        for name in [".zshrc", "safe\u{202E}txt"] {
            let unsafe = ShelfReceivedEntry(item: ShelfItem(kind: .file, name: name, data: Data([1])), receivedAt: Date())
            do {
                _ = try await store.save(unsafe, to: downloads)
                preconditionFailure("Unsafe filename accepted")
            } catch ShelfEngine.Failure.invalidItem {}
        }
        let long = ShelfReceivedEntry(item: ShelfItem(kind: .file,
            name: String(repeating: "a", count: 251) + ".txt", data: Data([1])), receivedAt: Date())
        _ = try await store.save(long, to: downloads)
        let collision = try await store.save(long, to: downloads)
        precondition(collision.lastPathComponent.utf8.count <= 255)
        let longExtension = ShelfReceivedEntry(item: ShelfItem(kind: .file,
            name: "a." + String(repeating: "x", count: 253), data: Data([1])), receivedAt: Date())
        _ = try await store.save(longExtension, to: downloads)
        do {
            _ = try await store.save(longExtension, to: downloads)
            preconditionFailure("Long extension collision accepted")
        } catch ShelfEngine.Failure.invalidItem {}
        try await store.remove(file)
        let remaining = try await store.entries()
        precondition(remaining.count == 1 && remaining[0].item.kind == .text)
        try Data("broken".utf8).write(to: store.directory.appendingPathComponent("broken.json"))
        let readable = try await store.entries()
        precondition(readable.count == 1)
        try await store.clear()
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        precondition(files.isEmpty)
        let cleared = try await store.entries()
        precondition(cleared.isEmpty)
        print("Shelf received: quarantine, unsafe names, 255-byte collisions, corrupt entries, clear passed")
    }
}
