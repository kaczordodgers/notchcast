// notchcast-sources: Tinycast/Features/AgentChatTools/Model/*.swift
// notchcast-sources: Tinycast/Features/AI/Model/AIRequest.swift Tinycast/Features/AI/Model/AITool.swift
// notchcast-sources: Tinycast/Features/AI/Model/JSONValue.swift Tinycast/Features/AI/Service/AIProvider.swift
// notchcast-sources: Tinycast/Features/AI/Service/AIToolLoopProvider.swift
import Foundation
import Synchronization

final class CompletionFake: AIProvider, Sendable {
    let requests = Mutex<[AIRequest]>([])
    func stream(_ request: AIRequest) -> AIProviderStream {
        requests.withLock { $0.append(request) }
        return AIProviderStream { stream in
            stream.yield(.text("Let me check the file."))
            stream.yield(.finished)
            stream.finish()
        }
    }
}

@main
struct CompletionTests {
    static func main() async throws {
        for (text, unfinished) in [
            ("Let me check the file.", true),
            ("Done: wrote notes.md.", false),
            ("Blocked: no permission to read Mail.", false),
            ("Let me summarize:\nThe file contains three entries.", false),
            ("Found the file. Now let me verify it.", true),
            ("I'll now inspect the file.", true),
            ("Let me check the file. It contains three entries.", false),
            ("I'll fix it once you confirm.", false),
            ("Let me know if you need more.", false)
        ] {
            precondition(AgentTurnCompletion.isUnfinished(text) == unfinished, text)
        }
        print("PASS: 9 detector cases")
        for enabled in [false, true] {
            let fake = CompletionFake()
            let tool = AITool(name: "read", description: "Read", parameters: .object([:]), origin: "Test")
            let provider = AIToolLoopProvider(
                base: fake, tools: [tool], maxRounds: 8, completionEnabled: enabled
            ) { _ in fatalError("A tool-less continuation must not invoke tools") }
            var finished = 0
            var shown = ""
            for try await event in provider.stream(AIRequest(messages: [.init(role: .user, text: "Check")])) {
                if event == .finished { finished += 1 }
                if case .text(let delta) = event { shown += delta }
            }
            precondition(!shown.contains(".Let me"), "Continued reply must not run into the first one")
            let requests = fake.requests.withLock { $0 }
            guard requests.count == (enabled ? 2 : 1) else {
                print("FAIL: enabled=\(enabled), expected \(enabled ? 2 : 1) requests, got \(requests.count)")
                exit(1)
            }
            precondition(finished == 1)
            precondition(requests[0].instructions?.contains(AgentTurnCompletion.rule) == (enabled ? true : nil))
            if enabled {
                precondition(requests[1].messages.last?.text == AgentTurnCompletion.continuation)
                precondition(requests[1].messages.dropLast().last?.text == "Let me check the file.")
            }
            print("PASS: enabled=\(enabled), requests=\(requests.count), finished=\(finished)")
        }
    }
}
