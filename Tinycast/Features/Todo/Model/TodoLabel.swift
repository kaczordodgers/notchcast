import Foundation

struct TodoLabel: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var order = 0
}
