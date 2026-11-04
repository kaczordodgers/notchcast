import Foundation

struct CommandRunnerToken {
    private let store = KeychainSecretStore(scope: "command-runner")
    private let account = UUID(uuidString: "21582F44-E71A-467C-8EFA-55EB25D83F00")!

    func read() throws -> String? { try store.secret(for: account) }
    func set(_ token: String) throws { try store.setSecret(token, for: account) }
    func remove() throws { try store.removeSecret(for: account) }
}
