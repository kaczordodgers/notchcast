import Foundation

extension AgentMCPModule {
    func configure(index: AgentActionIndex) {
        engine.configure(backend: AgentMCPIndexBackend(index: index))
        index.receiveMCP = { [weak self] request in
            guard let self, let session = request.id else { throw AgentReply.Code.notRunning }
            if request.parameters == .null {
                engine.endSession(session)
                return .null
            }
            guard case .string(let line) = request.parameters else { throw AgentReply.Code.badRequest }
            guard let output = await engine.receive(line: Data(line.utf8), session: session) else { return .null }
            guard let text = String(bytes: output, encoding: .utf8) else { throw AgentReply.Code.failed }
            return .string(text)
        }
    }
}
