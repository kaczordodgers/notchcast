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
    /// A second, quieter line under the text, for what to do next.
    var detail: String? = nil
}
