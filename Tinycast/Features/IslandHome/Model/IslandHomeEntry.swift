import Foundation

struct IslandHomeEntry: Identifiable, Codable, Equatable, Sendable {
    struct ID: Hashable, Codable, Sendable {
        let source: String
        let key: String
    }

    enum State: Int, Codable, Sendable {
        case failure, attention, active, playing, message, result
    }

    let id: ID
    var state: State
    var title: String
    var detail: String?
    var priority: Int = 0
    var date: Date
    var expires: Date?
    var progress: Double?

    var isValid: Bool {
        !id.source.isEmpty && !id.key.isEmpty && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && date.timeIntervalSinceReferenceDate.isFinite
            && (expires?.timeIntervalSinceReferenceDate.isFinite ?? true)
    }
}
