import Foundation

struct AudioPriorityDevice: Equatable, Sendable {
    enum Direction: String, Codable, CaseIterable, Sendable {
        case output, input
    }

    let uid: String
    let name: String
    let direction: Direction
}
