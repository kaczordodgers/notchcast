import Foundation

enum AppearanceSurfaceStyle: String, CaseIterable, Identifiable, Sendable {
    case glass, black, matte

    static let defaultsKey = "notchcast.appearance.surface"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: String(localized: "Glass", table: "Notchcast")
        case .black: String(localized: "Black", table: "Notchcast")
        case .matte: String(localized: "Matte", table: "Notchcast")
        }
    }

    func fill(dark: Bool) -> (white: Double, alpha: Double)? {
        switch self {
        case .glass: nil
        case .black: (0, 1)
        case .matte: dark ? (0, 0.42) : (1, 0.68)
        }
    }
}
