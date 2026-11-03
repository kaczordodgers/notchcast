import Foundation

enum IslandPage: Int, CaseIterable, Identifiable, Sendable {
    case home = 1, day

    var id: Self { self }
    var key: String { String(rawValue) }

    var title: LocalizedStringResource {
        switch self {
        case .home: "Home"
        case .day: "Day"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .day: "calendar"
        }
    }

    static func page(forKey key: String) -> Self? {
        Int(key).flatMap(Self.init(rawValue:))
    }

    func landingPage(hasLiveActivities: Bool) -> Self {
        self == .home && !hasLiveActivities ? .day : self
    }
}
