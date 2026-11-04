import Foundation

struct IslandHomeModel: Sendable {
    static let historyLimit = 50
    static let recentLimit = 3
    static let liveLimit = 20

    private(set) var history: [IslandHomeEntry] = []
    private var cleared: [[IslandHomeEntry]] = []
    var canUndo: Bool { !cleared.isEmpty }

    init(history: [IslandHomeEntry] = []) {
        self.history = Self.normalized(history.filter { $0.state == .result })
            .prefix(Self.historyLimit).map { $0 }
    }

    mutating func retain(_ entry: IslandHomeEntry) {
        guard entry.state == .result else { return }
        history = Array(Self.normalized(history + [entry]).prefix(Self.historyLimit))
    }

    mutating func clear(_ id: IslandHomeEntry.ID) {
        let removed = history.filter { $0.id == id }
        guard !removed.isEmpty else { return }
        cleared.append(removed)
        history.removeAll { $0.id == id }
    }

    mutating func clearAll() {
        guard !history.isEmpty else { return }
        cleared.append(history)
        history = []
    }

    mutating func undoClear() {
        guard let restored = cleared.popLast() else { return }
        history = Array(Self.normalized(history + restored).prefix(Self.historyLimit))
    }

    mutating func close() { cleared = [] }

    func entries(live: [IslandHomeEntry], now: Date) -> [IslandHomeEntry] {
        let current = Self.normalized(live.filter { $0.state != .result })
            .filter { $0.expires.map { now < $0 } ?? true }
        let ids = Set(current.map(\.id))
        let recent = history.filter {
            !ids.contains($0.id) && ($0.expires.map { now < $0 } ?? true)
        }.prefix(Self.recentLimit)
        return Array(current.sorted(by: Self.ranksBefore).prefix(Self.liveLimit)) + recent
    }

    private static func ranksBefore(_ lhs: IslandHomeEntry, _ rhs: IslandHomeEntry) -> Bool {
        if lhs.state != rhs.state { return lhs.state.rawValue < rhs.state.rawValue }
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        return newestFirst(lhs, rhs)
    }

    private static func newestFirst(_ lhs: IslandHomeEntry, _ rhs: IslandHomeEntry) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.id.source != rhs.id.source { return lhs.id.source < rhs.id.source }
        return lhs.id.key < rhs.id.key
    }

    private static func normalized(_ entries: [IslandHomeEntry]) -> [IslandHomeEntry] {
        var values: [IslandHomeEntry.ID: IslandHomeEntry] = [:]
        for var entry in entries where entry.isValid {
            if let old = values[entry.id], old.date > entry.date { continue }
            entry.progress = entry.progress.flatMap { $0.isFinite ? min(max($0, 0), 1) : nil }
            values[entry.id] = entry
        }
        return values.values.sorted(by: newestFirst)
    }
}
