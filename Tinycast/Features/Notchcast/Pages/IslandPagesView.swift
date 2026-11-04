import SwiftUI

struct IslandPagesView: View {
    @Environment(IslandController.self) private var island
    @Environment(IslandPagesCoordinator.self) private var pages
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        pages.content(island.page)
            .id(island.page)
            .transition(.opacity)
            .animation(reduceMotion ? nil : NotchcastTheme.Motion.pageChange, value: island.page)
    }
}
