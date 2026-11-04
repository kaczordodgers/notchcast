import Foundation

struct CommandQuickAdd: Sendable {
    enum Failure: Error, Sendable { case emptyText, missingToken, failed }

    let readToken: @Sendable () throws -> String?
    let client: @Sendable (_ text: String, _ token: String) async throws -> Bool

    func add(_ text: String) async throws(Failure) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .emptyText }
        do {
            try Task.checkCancellation()
            guard let token = try readToken(), !token.isEmpty else { throw Failure.missingToken }
            guard try await client(text, token) else { throw Failure.failed }
            try Task.checkCancellation()
        } catch Failure.missingToken {
            throw .missingToken
        } catch {
            throw .failed
        }
    }
}
