import Foundation

struct TodoProject: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var order = 0
    var externalRef: String?
}
