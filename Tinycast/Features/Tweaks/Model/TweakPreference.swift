import Foundation

nonisolated struct TweakPreference: Hashable, Codable, Sendable {
    let domain: String
    let key: String
    var currentHost = false
}
