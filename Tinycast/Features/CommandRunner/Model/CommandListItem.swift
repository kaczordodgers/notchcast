import Foundation

struct CommandListItem: Codable, Identifiable, Sendable, Equatable {
    enum Target: Codable, Sendable, Equatable {
        case url(URL)
        case copy(String)
        case command(id: String, arguments: [String])
    }

    struct Action: Codable, Sendable, Equatable {
        let title: String
        let target: Target
    }

    let id: String
    let title: String
    var detail: String?
    var icon: String?
    let target: Target
    var actions: [Action] = []
}
