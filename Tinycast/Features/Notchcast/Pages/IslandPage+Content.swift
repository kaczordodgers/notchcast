import SwiftUI

extension IslandPage {
    func content(day: IslandDayPage) -> AnyView {
        switch self {
        case .home: AnyView(IslandHomeView())
        case .day: AnyView(IslandDayView(page: day))
        }
    }

    @MainActor func refresh(day: IslandDayPage) {
        switch self {
        case .home: break
        case .day: day.refresh()
        }
    }
}
