import SwiftUI

struct IslandContentView: View {
    var content: AnyView
    var headerHeight: CGFloat
    var onHeight: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: headerHeight).accessibilityHidden(true)
            content
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
