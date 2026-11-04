import Foundation
import Security

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "notchcast-gallery-probe-" + UUID().uuidString,
    kSecMatchLimit as String: kSecMatchLimitOne,
    kSecReturnData as String: true
]
var result: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &result)
print("keychain probe: SecItemCopyMatching = \(status)")
guard status == errSecParam || status == errSecNotAvailable else {
    print("keychain probe: FAIL (query reached Keychain or returned an unexpected status)")
    exit(1)
}
print("keychain probe: PASS (service access denied)")
