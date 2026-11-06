import Foundation

struct IslandMessage: Identifiable {
    enum Tone {
        case neutral
        case success
        case warning
        case danger
    }

    let id: UUID
    let tone: Tone
    let text: String
    let isProgress: Bool
    let onCancel: (() -> Void)?
    /// A second line under the title; a closed island shows at most title and description.
    var detail: String?
    /// The subject's own symbol (AirPods), in place of the tone's.
    var symbol: String?
    /// A value beside the text (AirPods' battery).
    var value: IslandValue?

    init(id: UUID, tone: Tone, text: String, isProgress: Bool, onCancel: (() -> Void)?,
         detail: String? = nil, symbol: String? = nil, value: IslandValue? = nil) {
        self.id = id
        self.tone = tone
        self.text = text
        self.isProgress = isProgress
        self.onCancel = onCancel
        self.detail = detail
        self.symbol = symbol
        self.value = value.map(IslandValue.clamped)
    }

    var shownSymbol: String {
        if let symbol { return symbol }
        if isProgress { return "progress.indicator" }
        return switch tone {
        case .neutral: "info"
        case .success: "checkmark"
        case .warning, .danger: "exclamationmark"
        }
    }
}
