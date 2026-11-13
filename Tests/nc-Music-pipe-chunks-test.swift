// notchcast-sources: Tinycast/Features/Music/Service/FileHandle+Chunks.swift
import Foundation

@main
struct PipeChunksTest {
    static func main() async throws {
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) {
            print("FAIL: idle readers held the cooperative pool")
            exit(1)
        }
        try await delivers()
        await idleReadersHoldNoPoolThread()
        print("PASS: pipe chunks arrive in order, end at EOF, and idle readers leave the pool free")
    }

    static func delivers() async throws {
        let pipe = Pipe()
        let reader = Task {
            var received = Data()
            for await chunk in pipe.fileHandleForReading.chunks() { received.append(chunk) }
            return received
        }
        try pipe.fileHandleForWriting.write(contentsOf: Data("one\n".utf8))
        try pipe.fileHandleForWriting.write(contentsOf: Data("two\n".utf8))
        try pipe.fileHandleForWriting.close()
        let received = await reader.value
        precondition(received == Data("one\ntwo\n".utf8), "every chunk arrives and EOF ends the stream")
        precondition(pipe.fileHandleForReading.readabilityHandler == nil, "EOF clears the handler")
    }

    static func idleReadersHoldNoPoolThread() async {
        let width = ProcessInfo.processInfo.activeProcessorCount * 4
        let pipes = (0..<width).map { _ in Pipe() }
        let readers = pipes.map { pipe in
            Task.detached(priority: .utility) {
                var count = 0
                for await _ in pipe.fileHandleForReading.chunks() { count += 1 }
                return count
            }
        }
        try? await Task.sleep(for: .milliseconds(200))
        let free = await Task.detached { 42 }.value
        precondition(free == 42, "the pool still runs work while \(width) readers wait")
        for reader in readers { reader.cancel() }
        for reader in readers {
            let count = await reader.value
            precondition(count == 0, "a cancelled reader ends without data")
        }
        precondition(pipes.allSatisfy { $0.fileHandleForReading.readabilityHandler == nil },
                     "cancelling a reader clears its handler")
    }
}
