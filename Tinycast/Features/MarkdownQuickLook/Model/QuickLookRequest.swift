import Foundation

struct QuickLookRequest: Identifiable, Sendable, Equatable {
    let id: UUID
    let fileURL: URL
}
