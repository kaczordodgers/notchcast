import Foundation

struct FanOwnershipJournal: Codable, Sendable, Equatable {
    private(set) var applied = "auto"
    private(set) var intent: String?
    private(set) var needsUndo = false
    private(set) var failures = 0
    private(set) var retryAt: Date?

    mutating func begin(_ mode: String) {
        if intent != mode { failures = 0; retryAt = nil }
        intent = mode
        if mode != "auto" { needsUndo = true }
    }

    mutating func succeed(_ mode: String) {
        applied = mode
        intent = nil
        failures = 0
        retryAt = nil
        needsUndo = mode != "auto"
    }

    mutating func fail(now: Date) {
        failures += 1
        retryAt = now.addingTimeInterval(60 * pow(2, Double(failures - 1)))
    }

    func mayRetry(now: Date) -> Bool {
        failures < 6 && (retryAt.map { now >= $0 } ?? true)
    }
}
