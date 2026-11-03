import SwiftUI

struct IslandContentView: View {
    var content: AnyView
    var header: AnyView
    var headerHeight: CGFloat
    var onHeight: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: headerHeight)
            content
                .environment(\.islandHeaderHeight, headerHeight)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Theme.Colors.textPrimary)
        .environment(\.colorScheme, .dark)
        .motionScope()
    }
}
