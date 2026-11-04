import Foundation

enum DictationDestination: String, CaseIterable, Identifiable, Sendable {
    case paste
    case copy
    case both
    case voiceAsk

    static let allCases: [Self] = [.paste, .copy, .both]

    var id: Self { self }
    var title: String {
        switch self {
        case .paste: String(localized: "Paste in active app")
        case .copy: String(localized: "Copy to clipboard")
        case .both: String(localized: "Paste and copy")
        case .voiceAsk: String(localized: "Voice Ask")
        }
    }

    var pastes: Bool { self == .paste || self == .both }
    var copies: Bool { self == .copy || self == .both }
}
