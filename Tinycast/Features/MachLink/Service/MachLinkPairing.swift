import Foundation
import Security
import CryptoKit

struct MachLinkPairing: Sendable {
    let id: UUID
    let secret: Data

    var discoveryHash: String {
        WebRules.hex(SHA256.hash(data: Data(id.uuidString.utf8)).prefix(12))
    }

    init(id: UUID, secret: Data) throws {
        guard secret.count == 32 else { throw MachLinkMessage.Failure.invalidPairing }
        self.id = id
        self.secret = secret
    }

    static func create() throws -> Self {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw KeychainSecretStore.StoreError.keychain(status) }
        return try Self(id: UUID(), secret: Data(bytes))
    }

    func save(to store: KeychainSecretStore) throws {
        try store.setSecret(secret.base64EncodedString(), for: id)
    }

    static func load(id: UUID, from store: KeychainSecretStore) throws -> Self? {
        guard let value = try store.secret(for: id) else { return nil }
        guard let bytes = Data(base64Encoded: value) else { throw MachLinkMessage.Failure.invalidPairing }
        return try Self(id: id, secret: bytes)
    }
}
