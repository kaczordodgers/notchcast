import Foundation

@MainActor
struct VoiceAskCLITransport: VoiceAskTransport {
    struct Output: Sendable {
        let status: Int32
        let stdout: Data
    }

    private struct Reply: Decodable {
        let status: String
        let reply: String?
        let error: String?
    }

    let resolve: @MainActor () -> URL?
    let run: @MainActor (URL, [String], Data) async throws -> Output

    func send(_ text: String, destination: String) async throws -> VoiceAskResult {
        guard !destination.isEmpty, !destination.contains(where: \.isWhitespace) else {
            throw VoiceAskCLIError.invalidDestination
        }
        guard let executable = resolve() else { throw VoiceAskCLIError.missingCLI }
        let output = try await run(executable, ["thread", "send", "--wait", "--json", destination, "-"], Data(text.utf8))
        try Task.checkCancellation()
        guard let reply = try? JSONDecoder().decode(Reply.self, from: output.stdout) else {
            throw VoiceAskCLIError.invalidOutput
        }
        if output.status == 2 || reply.status == "waiting" {
            return VoiceAskResult(state: .running, firstLines: [
                String(localized: "The agent is waiting for an answer in T3 Code.")
            ])
        }
        if output.status == 1, let error = reply.error {
            return VoiceAskResult(state: .failed, firstLines: error.components(separatedBy: .newlines))
        }
        guard output.status == 0, reply.status == "completed", let text = reply.reply else {
            throw VoiceAskCLIError.invalidOutput
        }
        return VoiceAskResult(state: .completed, firstLines: text.components(separatedBy: .newlines))
    }

    static func production() -> Self {
        Self(resolve: {
            let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            return (paths.map { URL(filePath: $0).appending(path: "t3") } + [URL(filePath: "/opt/homebrew/bin/t3")])
                .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        }, run: { try await VoiceAskProcessRunner.run($0, arguments: $1, input: $2) })
    }
}
