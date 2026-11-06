import AppKit
import SwiftUI

extension AppearanceThemeColors {
    func ramp(dark: Double, light: Double, role: AppearanceThemeColors.Role = .text) -> Color {
        _ = revision
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return self.ink(role, in: appearance, dark: dark, light: light)
                ?? NSColor(srgbRed: isDark ? 1 : 0, green: isDark ? 1 : 0,
                           blue: isDark ? 1 : 0, alpha: isDark ? dark : light)
        })
    }
}

/// Set by the launcher hung from the island (`NotchcastLauncherSurface`): its backdrop is then the island's black.
@MainActor @Observable final class AppearanceIslandBackdrop {
    static let shared = AppearanceIslandBackdrop()
    var attached = false
}

extension AppearanceThemeColors {
    /// A launcher hung from the island is the island's black, not glass.
    @MainActor static func backdrop(hidden: Bool) -> AnyShapeStyle {
        if AppearanceIslandBackdrop.shared.attached, !hidden { return AnyShapeStyle(Color.black) }
        return hidden ? AnyShapeStyle(Color.clear) : AnyShapeStyle(shared.backdrop)
    }

    static func tinted(_ glass: Glass) -> Glass {
        guard shared.hasPalette else { return glass }
        return glass.tint(shared.background(.background))
    }

    private var backdrop: LinearGradient {
        _ = revision
        return LinearGradient(
            stops: [
                .init(color: background(.background), location: 0),
                .init(color: background(.backgroundSecondary), location: 0.7)
            ], startPoint: .top, endPoint: .bottom)
    }

    private func background(_ role: AppearanceThemeColors.Role) -> Color {
        Color(nsColor: dynamicColor(role, dark: 1, light: 1, fallback: .clear))
    }
}
