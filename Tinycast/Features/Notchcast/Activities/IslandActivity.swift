import Foundation

struct IslandActivity: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case timer
        case transfer
        case status
    }

    /// Only error and warning get colour (look-decisions, Messages).
    enum Tone: Sendable {
        case plain
        case warning
        case error
    }

    /// A meeting about to start: the closed island shows it as a card with Join.
    struct Meeting: Equatable, Sendable {
        var start: Date
        /// The calendar's sRGB colour as red, green and blue.
        var tint: [Double]?
        var link: URL?
    }

    let id: UUID
    var kind: Kind
    var meeting: Meeting?
    var priority: Int
    var title: String
    var progress: Double?
    var endDate: Date?
    /// The state's own symbol; nil keeps the kind's.
    var symbol: String?
    /// The most exact value the producer knows; nil falls back to end date, then progress, then a spinner.
    var value: IslandValue?
    var tone: Tone

    init(id: UUID = UUID(), kind: Kind, priority: Int = 0, title: String,
         progress: Double? = nil, endDate: Date? = nil, symbol: String? = nil, value: IslandValue? = nil,
         tone: Tone = .plain, meeting: Meeting? = nil) {
        self.id = id
        self.kind = kind
        self.meeting = meeting
        self.priority = priority
        self.title = title
        self.progress = progress.map { min(max($0, 0), 1) }
        self.endDate = endDate
        self.symbol = symbol
        self.value = value.map(IslandValue.clamped)
        self.tone = tone
    }

    var shownValue: IslandValue { value ?? .fallback(progress: progress, endDate: endDate) }

    var shownSymbol: String {
        if let symbol { return symbol }
        return switch kind {
        case .timer: "timer"
        case .transfer: "arrow.up.arrow.down"
        case .status: "info"
        }
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
