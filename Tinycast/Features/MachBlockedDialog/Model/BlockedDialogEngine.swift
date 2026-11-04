import Foundation

struct BlockedDialogWindow: Codable, Hashable, Sendable {
    let owner: String
    let processID: Int
    let windowID: Int
    let layer: Int
    let width: Double
    let height: Double

    var isCandidate: Bool {
        ["UserNotificationCenter", "universalAccessAuthWarn", "SecurityAgent", "CoreServicesUIAgent"]
            .contains(owner) && processID > 0 && windowID > 0 && layer > 0
            && width.isFinite && height.isFinite && width > 0 && height > 0
    }
}

struct BlockedDialogEngine {
    private var announced: Set<BlockedDialogWindow> = []
    private var lastAlert: Date?
    let cooldown: TimeInterval = 60

    mutating func evaluate(_ windows: [BlockedDialogWindow], now: Date) -> BlockedDialogWindow? {
        let candidates = windows.filter(\.isCandidate)
        announced.formIntersection(candidates)
        guard lastAlert.map({ now.timeIntervalSince($0) >= cooldown }) ?? true,
              let next = candidates.first(where: { !announced.contains($0) }) else { return nil }
        announced.insert(next)
        lastAlert = now
        return next
    }
}
