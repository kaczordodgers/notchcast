import SwiftUI

extension EnvironmentValues {
    @Entry var hasHardwareNotch = false
}

struct IslandClosedView: View {
    var context: IslandClosedContext
    var content: IslandController.ClosedContent
    var cameraWidth: CGFloat
    var bandHeight: CGFloat
    var message: IslandMessage?
    @State private var leadingWidth: CGFloat = 0
    @State private var trailingWidth: CGFloat = 0
    var onWidth: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 0) {
        if cameraWidth == 0, let message {
            IslandStatusView(message: message)
                .frame(height: bandHeight)
        } else {
        HStack(spacing: Theme.Spacing.md) {
            content.leading
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { leadingWidth = $0 }
                .frame(width: cameraWidth > 0 ? wingWidth : nil)
            if cameraWidth > 0 {
                Color.clear.frame(width: cameraWidth).accessibilityHidden(true)
            }
            content.trailing
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { trailingWidth = $0 }
                .frame(width: cameraWidth > 0 ? wingWidth : nil)
        }
        .fixedSize()
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: bandHeight)
        }
        if cameraWidth > 0, let message {
            IslandStatusView(message: message)
                .frame(height: NotchcastTheme.statusHeight)
        }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { onWidth($0) }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Theme.Colors.textPrimary)
        .environment(\.colorScheme, .dark)
        .motionScope()
    }

    private var wingWidth: CGFloat {
        context.wingWidth(contentWidth: max(leadingWidth, trailingWidth), minimum: NotchcastTheme.minimumWing)
    }
}
