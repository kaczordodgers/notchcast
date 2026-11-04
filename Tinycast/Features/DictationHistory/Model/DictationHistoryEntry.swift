import Foundation

struct DictationHistoryEntry: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let date: Date
    let raw: String
    let cleaned: String
}
