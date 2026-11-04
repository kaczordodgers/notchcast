import SwiftUI

extension IslandPage {
    func content(day: IslandDayPage, homeRevision: UUID) -> AnyView {
        switch self {
        case .home: AnyView(IslandHomeView().id(homeRevision))
        case .day: AnyView(IslandDayView(page: day))
        }
    }
}
