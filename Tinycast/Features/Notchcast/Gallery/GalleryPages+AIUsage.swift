#if DEBUG
import SwiftUI

extension GalleryPages {
    static func aiUsage(_ core: AppCore) -> [GalleryPage] {
        [true, false].map { dark in
            GalleryPage(name: "island-usage-\(dark ? "dark" : "light")", types: ["AIUsagePageView"], makeWindow: {
                // A saved gateway answer renders the page as it reads now, for a live-data proof.
                let live = ProcessInfo.processInfo.environment["NOTCHCAST_GALLERY_QUOTAS"].map(URL.init(fileURLWithPath:))
                let now = live != nil ? .now : (try? Date("2026-11-11T22:30:00Z", strategy: .iso8601)) ?? .now
                let fixture = live ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                    .appending(path: "../../../../Tests/Fixtures/ai-usage/magpie-quotas.json").standardizedFileURL
                let snapshots = (try? MagpieQuotaDecoder.decode(Data(contentsOf: fixture), now: now)) ?? []
                let view = VStack(spacing: 0) {
                    AIUsagePageView(content: .accounts(snapshots.map(AIUsageAccount.init)), now: now)
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
