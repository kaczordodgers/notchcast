import SwiftUI

struct IslandContentView: View {
    var content: AnyView
    var header: AnyView
    var headerHeight: CGFloat
    var onHeight: (CGFloat) -> Void
    @Environment(\.hasHardwareNotch) private var hasHardwareNotch

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: headerHeight)
            content
                .environment(\.islandHeaderHeight, headerHeight)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        }
        // Beside a camera the silhouette's sides stand in by its shoulders; the pages keep their inset.
        .padding(.horizontal, hasHardwareNotch ? NotchcastTheme.openShoulder : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.Colors.textPrimary)
        .environment(\.colorScheme, .dark)
        .motionScope()
    }
}
