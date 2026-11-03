import Foundation

struct IslandMessage: Identifiable {
    enum Tone {
        case neutral
        case success
        case danger
    }

    let id: UUID
    let tone: Tone
    let text: String
    let isProgress: Bool
    let onCancel: (() -> Void)?
}
