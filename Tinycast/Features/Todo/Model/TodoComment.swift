import Foundation

struct TodoComment: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var text: String
    var createdAt: Date
}
