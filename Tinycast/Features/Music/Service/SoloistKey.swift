import Foundation
import OSLog
import Security

@MainActor
final class SoloistKey {
    private static let account = UUID(uuidString: "8CA166D0-0F2B-45CD-9306-B2CD5640EC54")!
    private let presence: (() throws -> Bool)?
    private let read: () throws -> String?
    private let write: (String?) throws -> Void
    var onChange: (() -> Void)?

    convenience init(store: KeychainSecretStore = KeychainSecretStore(scope: "soloist")) {
        self.init(read: { try store.secret(for: Self.account) }, write: { key in
            if let key { try store.setSecret(key, for: Self.account) } else { try store.removeSecret(for: Self.account) }
        }, presence: { try store.hasSecret(for: Self.account) })
    }

    init(read: @escaping () throws -> String?, write: @escaping (String?) throws -> Void,
         presence: (() throws -> Bool)? = nil) {
        self.presence = presence
        self.read = read
        self.write = write
    }

    var isSaved: Bool {
        get throws {
            guard let presence else { return try value() != nil }
            do { return try presence() } catch { throw Self.failure(.keyUnavailable, error) }
        }
    }

    func value() throws -> String? {
        do { return try read().map(SoloistKeyValidation.validated) } catch { throw Self.failure(.keyUnavailable, error) }
    }

    func save(_ pasted: String) throws {
        let key: String
        do { key = try SoloistKeyValidation.validated(pasted) } catch {
            throw Self.failure(.invalidKey, "\(pasted.count) characters, \(SoloistFailure.describe(error))")
        }
        do { try write(key) } catch { throw Self.failure(.keyNotSaved, error) }
        onChange?()
    }

    /// Reads at most one key's worth of bytes; every refusal names the file and what was read.
    func importKey(from file: URL) throws {
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            data = try handle.read(upToCount: SoloistKeyValidation.maximumBytes + 1) ?? Data()
        } catch { throw Self.failure(.keyFileUnreadable, "\(file.path): \(SoloistFailure.describe(error))") }
        let found = "\(file.path): \(data.count.formatted(.byteCount(style: .file)))"
        guard data.count <= SoloistKeyValidation.maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw Self.failure(.keyFileUnreadable, found)
        }
        do { try save(text) } catch let failure as SoloistFailure where failure.reason == .invalidKey {
            throw Self.failure(.invalidKey, "\(found), \(SoloistFailure.describe(failure))")
        }
    }

    func remove() throws {
        do { try write(nil) } catch { throw Self.failure(.keyNotSaved, error) }
        onChange?()
    }

    private static func failure(_ kind: SoloistFailure, _ error: any Error) -> SoloistFailure {
        let detail = switch error {
        case KeychainSecretStore.StoreError.keychain(let status):
            "Keychain: \(SecCopyErrorMessageString(status, nil) as String? ?? "error") (OSStatus \(status))"
        case KeychainSecretStore.StoreError.invalidEncoding: "Keychain: the item isn’t UTF-8 text"
        default: SoloistFailure.describe(error)
        }
        return failure(kind, detail)
    }

    /// Logged so a failure explains itself in Console; the detail never holds the key.
    private static func failure(_ kind: SoloistFailure, _ detail: String) -> SoloistFailure {
        let failure = kind.detail(detail)
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.tinycast.app", category: "Soloist")
            .error("API key: \(String(describing: failure), privacy: .public)")
        return failure
    }
}
