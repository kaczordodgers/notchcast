import Foundation

struct LiveTimerEntry: Identifiable, Equatable, Sendable, Codable {
    enum Kind: Sendable, Codable { case timer, alarm }
    enum Status: Sendable, Codable { case running, ringing, missed }

    let id: UUID
    let kind: Kind
    let label: String
    let end: Date
    var status: Status = .running

    func countdown(at now: Date) -> String {
        let seconds = Int(max(0, end.timeIntervalSince(now)).rounded(.up))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
