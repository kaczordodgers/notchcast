import Foundation

struct IslandActivity: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case timer
        case transfer
        case status
    }

    let id: UUID
    var kind: Kind
    var priority: Int
    var title: String
    var progress: Double?
    var endDate: Date?

    init(id: UUID = UUID(), kind: Kind, priority: Int = 0, title: String,
         progress: Double? = nil, endDate: Date? = nil) {
        self.id = id
        self.kind = kind
        self.priority = priority
        self.title = title
        self.progress = progress.map { min(max($0, 0), 1) }
        self.endDate = endDate
    }

    func outranks(_ other: Self) -> Bool {
        if (kind == .status) != (other.kind == .status) { return kind != .status }
        if priority != other.priority { return priority > other.priority }
        switch (endDate, other.endDate) {
        case let (next?, best?): return next < best
        case (.some, nil): return true
        default: return false
        }
    }
}
