import Foundation

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

    var isSaved: Bool { get throws { try presence?() ?? (value() != nil) } }

    func value() throws -> String? {
        do { return try read().map(SoloistKeyValidation.validated) } catch { throw SoloistFailure.keyUnavailable }
    }

    func save(_ pasted: String) throws {
        let key = try SoloistKeyValidation.validated(pasted)
        do { try write(key) } catch { throw SoloistFailure.keyUnavailable }
        onChange?()
    }

    func importKey(from file: URL) throws {
        let text = try Self.readFile(file)
        try save(text)
    }

    func remove() throws {
        do { try write(nil) } catch { throw SoloistFailure.keyUnavailable }
        onChange?()
    }

    private static func readFile(_ file: URL) throws -> String {
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: SoloistKeyValidation.maximumBytes + 1) ?? Data()
            guard data.count <= SoloistKeyValidation.maximumBytes, let text = String(data: data, encoding: .utf8) else {
                throw SoloistFailure.keyFileUnreadable
            }
            return text
        } catch { throw SoloistFailure.keyFileUnreadable }
    }
}
