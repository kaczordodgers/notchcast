import Foundation

struct IslandActivity: Identifiable, Equatable, Sendable {
    enum Kind: Sendable {
        case timer
        case transfer
        case status
    }

    /// The most exact thing a state knows, one case per row of the look table; the closed island shows nothing else.
    enum Value: Equatable, Sendable {
        /// A timer, a countdown, keep awake: counts down to the date.
        case timeLeft(Date)
        /// A recording, a walk: counts up from the date.
        case elapsed(since: Date)
        /// 0...1.
        case percent(Double)
        /// X of Y items, files or agents.
        case count(Int, of: Int)
        /// Step X of Y of a staged job.
        case step(Int, of: Int)
        /// A live reading the producer has already formatted with its unit ("184 Mb/s").
        case number(String)
        /// Listening, a camera in use, a watched change, keep awake without an end.
        case onOff(Bool)
        /// The state knows nothing better.
        case spinner

        var percent: Double? {
            if case let .percent(fraction) = self { return fraction }
            return nil
        }

        var endDate: Date? {
            if case let .timeLeft(date) = self { return date }
            return nil
        }
    }

    let id: UUID
    var kind: Kind
    var priority: Int
    var title: String
    /// The producer's own glyph; nil draws the kind's.
    var symbol: String?
    var value: Value?
    /// The one thing to do about it, as a button title ("Join", "Stop"); the centre runs it.
    var action: String?

    var progress: Double? { value?.percent }
    var endDate: Date? { value?.endDate }

    init(id: UUID = UUID(), kind: Kind, priority: Int = 0, title: String, symbol: String? = nil,
         value: Value? = nil, action: String? = nil) {
        self.id = id
        self.kind = kind
        self.priority = priority
        self.title = title
        self.symbol = symbol
        self.value = value.map(Self.clamped)
        self.action = action
    }

    /// The old producers' shape; one of `progress` or `endDate` is given, so a bare call takes the value init.
    init(id: UUID = UUID(), kind: Kind, priority: Int = 0, title: String, symbol: String? = nil,
         progress: Double?, endDate: Date? = nil) {
        self.init(id: id, kind: kind, priority: priority, title: title, symbol: symbol,
                  value: endDate.map(Value.timeLeft) ?? progress.map(Value.percent))
    }

    init(id: UUID = UUID(), kind: Kind, priority: Int = 0, title: String, symbol: String? = nil, endDate: Date?) {
        self.init(id: id, kind: kind, priority: priority, title: title, symbol: symbol, value: endDate.map(Value.timeLeft))
    }

    static func clamped(_ value: Value) -> Value {
        switch value {
        case let .percent(fraction): .percent(fraction.isFinite ? min(max(fraction, 0), 1) : 0)
        case let .count(done, of: total): .count(max(0, done), of: max(0, total))
        case let .step(done, of: total): .step(max(0, done), of: max(0, total))
        default: value
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
