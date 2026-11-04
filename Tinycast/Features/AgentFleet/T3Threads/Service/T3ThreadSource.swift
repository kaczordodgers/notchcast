import Foundation

struct T3ThreadSource: Sendable {
    typealias Runner = @Sendable () async throws -> Data
    let runner: Runner

    init(runner: @escaping Runner = T3ThreadProcessRunner.run) {
        self.runner = runner
    }

    func read() async throws -> [T3Thread] {
        let data = try await runner()
        try Task.checkCancellation()
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> [T3Thread] {
        let decoder = JSONDecoder()
        if let threads = try? decoder.decode([T3Thread].self, from: data) { return threads }
        return try decoder.decode(Envelope.self, from: data).threads
    }

    private struct Envelope: Decodable { let threads: [T3Thread] }
}
