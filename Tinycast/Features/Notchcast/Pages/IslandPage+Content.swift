import SwiftUI

extension IslandPage {
    @MainActor var isAvailable: Bool { self != .usage || NotchcastPreferences.shared.isEnabled(.aiUsage) }

    @MainActor func content(day: IslandDayPage, homeRevision: UUID) -> AnyView {
        switch self {
        case .home: AnyView(IslandHomeView().id(homeRevision))
        case .day: AnyView(IslandDayView(page: day))
        case .usage: AnyView(IslandUsageView(module: NotchcastCore.aiUsage))
        }
    }
}
