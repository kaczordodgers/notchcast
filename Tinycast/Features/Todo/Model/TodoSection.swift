import Foundation

struct TodoSection: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var projectID: String
    var order = 0
}
