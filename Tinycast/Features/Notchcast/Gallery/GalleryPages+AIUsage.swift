#if DEBUG
import SwiftUI

extension GalleryPages {
    /// The AI usage page with sample accounts above its gateway-down state. Dark is the island as drawn, on its
    /// black; light shows the view keeps to the ramp outside the island.
    static func aiUsage(_ core: AppCore) -> [GalleryPage] {
        [true, false].map { dark in
            GalleryPage(name: "island-usage-\(dark ? "dark" : "light")", types: ["AIUsagePageView"], makeWindow: {
                let now = Date.now
                let view = VStack(spacing: 0) {
                    AIUsagePageView(content: .accounts(AIUsageAccount.samples(now: now)), now: now)
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(height: 1)
                    AIUsagePageView(content: .gatewayDown, now: now)
                }
                .frame(width: NotchcastTheme.openMinimumWidth)
                .foregroundStyle(Theme.Colors.textPrimary)
                .background(dark ? NotchcastTheme.Colors.surface : Color.clear)
                .paletteEnvironment(core)
                let size = CGSize(width: NotchcastTheme.openMinimumWidth, height: NotchcastTheme.maximumHeight + 180)
                return window(view.frame(maxHeight: .infinity, alignment: .top), size: size, dark: dark)
            }, settle: .milliseconds(300))
        }
    }
}
#endif
