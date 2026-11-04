import Foundation
import LocalAuthentication
import Security

struct DictationCleanupSettingsStore {
    enum Failure: Error { case keychain(OSStatus), invalidKey }

    private let defaults: UserDefaults
    private let keychainService: String
    private static let settingsKey = "dictationCleanup"

    init(defaults: UserDefaults, bundleIdentifier: String) {
        self.defaults = defaults
        keychainService = bundleIdentifier + ".notchcast.dictation-cleanup"
    }

    static func live(bundleIdentifier: String) -> Self? {
        guard let defaults = UserDefaults(suiteName: bundleIdentifier + ".notchcast") else { return nil }
        return Self(defaults: defaults, bundleIdentifier: bundleIdentifier)
    }

    func read() throws -> DictationCleanupSettings {
        guard let data = defaults.data(forKey: Self.settingsKey) else { return .init() }
        return try JSONDecoder().decode(DictationCleanupSettings.self, from: data)
    }

    func save(_ settings: DictationCleanupSettings) throws {
        defaults.set(try JSONEncoder().encode(settings), forKey: Self.settingsKey)
    }

    func apiKey() throws -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let data = result as? Data, let key = String(bytes: data, encoding: .utf8) else {
            throw Failure.invalidKey
        }
        return key
    }

    func saveAPIKey(_ key: String) throws {
        let query = keychainQuery()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure.keychain(status) }
            return
        }
        let update = [kSecValueData as String: Data(trimmed.utf8)]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var addition = query
            addition[kSecValueData as String] = Data(trimmed.utf8)
            addition[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result = SecItemAdd(addition as CFDictionary, nil)
            guard result == errSecSuccess else { throw Failure.keychain(result) }
        } else if status != errSecSuccess {
            throw Failure.keychain(status)
        }
    }

    private func keychainQuery() -> [String: Any] {
        let context = LAContext()
        context.interactionNotAllowed = true
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "cliproxyapi",
            kSecUseAuthenticationContext as String: context
        ]
    }
}
