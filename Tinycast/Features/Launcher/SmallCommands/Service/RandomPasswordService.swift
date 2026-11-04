import Foundation
import Security

enum RandomPasswordService {
    static func make() throws -> String {
        try RandomPasswordEngine.make { count in
            var bytes = [UInt8](repeating: 0, count: count)
            guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
                throw RandomPasswordEngine.Failure.entropyUnavailable
            }
            return bytes
        }
    }
}
