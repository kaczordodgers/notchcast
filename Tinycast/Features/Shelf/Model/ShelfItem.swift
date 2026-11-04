import Foundation
import CryptoKit

struct ShelfItem: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case text, link, file }
    let kind: Kind
    let name: String
    let data: Data

    var fingerprint: String {
        SHA256.hash(data: Data((kind.rawValue + "\u{0}" + name + "\u{0}").utf8) + data)
            .map { String(format: "%02x", $0) }.joined()
    }
}
