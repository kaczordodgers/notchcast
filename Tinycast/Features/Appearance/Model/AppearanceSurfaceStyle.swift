import Foundation

enum AppearanceSurfaceStyle: String, CaseIterable, Identifiable, Sendable {
    case glass, black, matte

    static let defaultsKey = "notchcast.appearance.surface"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: String(localized: "Glass")
        case .black: String(localized: "Black")
        case .matte: String(localized: "Matte")
        }
    }
}
