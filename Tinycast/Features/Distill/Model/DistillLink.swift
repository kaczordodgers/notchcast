import Foundation

nonisolated struct DistillLink: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case waiting, failed }
    var id: UUID
    let url: String
    let added: Date
    var state: State
    var detail: String?
    var attempts: Int

    init(url: String, added: Date, state: State = .waiting, detail: String? = nil, attempts: Int = 0) {
        id = UUID()
        self.url = url
        self.added = added
        self.state = state
        self.detail = detail
        self.attempts = attempts
    }
}
