import Foundation

@MainActor
struct VoiceAskCLITransport: VoiceAskTransport {
    struct Output: Sendable {
        let status: Int32
        let stdout: Data
        var stderr = Data()
    }

    private struct Reply: Decodable {
        let status: String
        let reply: String?
        let error: String?
    }

    let resolve: @MainActor () async -> URL?
    let run: @MainActor (URL, [String], Data) async throws -> Output

    func send(_ text: String, destination: String) async throws -> VoiceAskResult {
        guard !destination.isEmpty, !destination.hasPrefix("-"), !destination.contains(where: \.isWhitespace) else {
            throw VoiceAskCLIError.invalidDestination
        }
        guard let executable = await resolve() else { throw VoiceAskCLIError.missingCLI }
        try Task.checkCancellation()
        let output = try await run(executable, ["thread", "send", "--wait", "--json", destination, "-"], Data(text.utf8))
        try Task.checkCancellation()
        let decoded = try? JSONDecoder().decode(Reply.self, from: output.stdout)
        if decoded?.status == "failed" || decoded?.error != nil || (output.status != 0 && output.status != 2) {
            let diagnostic = decoded?.error ?? String(decoding: output.stderr.prefix(500), as: UTF8.self)
            let message = decoded?.error == nil ? String(localized: "The T3 run stopped.", table: "Notchcast") : ""
            return VoiceAskResult(state: .failed, firstLines: ([message] + diagnostic.components(separatedBy: .newlines))
                .filter { !$0.isEmpty })
        }
        guard let reply = decoded else {
            throw VoiceAskCLIError.invalidOutput
        }
        if reply.status == "waiting" {
            return VoiceAskResult(state: .running, firstLines: [
                String(localized: "The agent is waiting for an answer in T3 Code.", table: "Notchcast")
            ])
        }
        guard output.status == 0, reply.status == "completed", let text = reply.reply else {
            throw VoiceAskCLIError.invalidOutput
        }
        return VoiceAskResult(state: .completed, firstLines: text.components(separatedBy: .newlines))
    }

    static func production() -> Self {
        Self(resolve: {
            await ExecutableLocator.locate("t3")
        }, run: { try await VoiceAskProcessRunner.run($0, arguments: $1, input: $2) })
    }
}
