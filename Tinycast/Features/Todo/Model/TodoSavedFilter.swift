import Foundation

struct TodoSavedFilter: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var query: String
    var order = 0
}
