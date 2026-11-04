import Foundation

protocol WaitingThreadSource: Sendable {
    func readWaitingThreads(in folder: URL) async throws -> [WaitingThread]
}

struct WaitingThread: Hashable, Sendable {
    enum Kind: String, Sendable { case approval, question, blocked }
    let id: String
    let title: String
    let kind: Kind

    static func leadReport(id: String, text: String) -> Self? {
        let kind: Kind
        if text.hasPrefix("QUESTION:") { kind = .question } else if text.hasPrefix("BLOCKED:") {
            kind = .blocked
        } else { return nil }
        let body = text.dropFirst(kind == .question ? 9 : 8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        return Self(id: "report:" + id, title: text, kind: kind)
    }
}
