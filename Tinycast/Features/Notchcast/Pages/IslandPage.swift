import Foundation

enum IslandPage: Int, CaseIterable, Identifiable, Sendable {
    case home = 1, day, usage

    var id: Self { self }
    var key: String { String(rawValue) }

    var title: LocalizedStringResource {
        switch self {
        case .home: "Home"
        case .day: LocalizedStringResource("Day", table: "Notchcast")
        case .usage: LocalizedStringResource("AI usage", table: "Notchcast")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .day: "calendar"
        case .usage: "gauge"
        }
    }

    static func page(forKey key: String) -> Self? {
        Int(key).flatMap(Self.init(rawValue:))
    }

    func landingPage(hasLiveActivities: Bool) -> Self {
        self == .home && !hasLiveActivities ? .day : self
    }

    @MainActor func refresh(home: () async -> Void, day: () async -> Void, usage: () async -> Void) async {
        switch self {
        case .home: await home()
        case .day: await day()
        case .usage: await usage()
        }
    }
}
