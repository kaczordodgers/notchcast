// notchcast-sources: Tinycast/Features/Shelf/Model/*.swift
// notchcast-sources: Tinycast/Features/Shelf/Service/ShelfLinkStatus.swift
// notchcast-sources: Tinycast/Features/Shelf/Service/ShelfReceivedStore.swift Tinycast/Features/Shelf/ShelfModule.swift
import Foundation

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@MainActor
final class FakeShelfTransport: ShelfTransport, ShelfLinkStatus {
    var shelfPeerAvailable = true
    var sent: [ShelfItem] = []
    func sendShelfItem(_ item: ShelfItem) async throws { sent.append(item) }
}

@main
struct ShelfTest {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let module = ShelfModule(directory: directory)
        let fake = FakeShelfTransport()
        module.transport = fake
        module.linkStatus = fake
        module.start()
        let text = ShelfItem(kind: .text, name: "text.txt", data: Data("hello".utf8))
        try await module.send(text)
        try await module.send(text)
        precondition(fake.sent.count == 2)
        for index in 0..<65 {
            try await module.send(ShelfItem(kind: .text, name: "item", data: Data("send \(index)".utf8)))
        }
        precondition(fake.sent.count == 67)
        for index in 0..<65 {
            _ = try await module.receive(ShelfItem(kind: .text, name: "item", data: Data("receive \(index)".utf8)))
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        precondition(entries.count == 64, "Stored \(entries.count) items")
        let received = try await module.receive(text)
        let duplicate = try await module.receive(text)
        precondition(received == duplicate)
        let stored = try JSONDecoder().decode(ShelfItem.self, from: Data(contentsOf: received))
        precondition(stored == text)
        for item in [
            ShelfItem(kind: .link, name: "link", data: Data("https://example.com".utf8)),
            ShelfItem(kind: .file, name: "sample.bin", data: Data([0, 1, 2]))
        ] { _ = try await module.receive(item) }
        let oversized = ShelfItem(kind: .file, name: "big", data: Data(repeating: 0, count: 24 * 1024 + 1))
        do { try await module.send(oversized); fatalError("accepted oversize") } catch ShelfEngine.Failure.oversized {}
        do { _ = try await module.receive(oversized); fatalError("received oversize") } catch ShelfEngine.Failure.oversized {}
        fake.shelfPeerAvailable = false
        do { try await module.send(text); fatalError("sent to down peer") } catch ShelfEngine.Failure.peerDown {}
        do {
            _ = try await module.receive(ShelfItem(kind: .file, name: "../escape", data: Data([1])))
            fatalError("accepted traversal")
        } catch ShelfEngine.Failure.invalidItem {}
        module.stop()
        do { _ = try await module.receive(text); fatalError("received while stopped") } catch ShelfEngine.Failure.stopped {}
        print("Shelf send, receive, size, peer-down, duplicate and path safety passed")
    }
}
