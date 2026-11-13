import AppKit
import Observation
import Synchronization

@Observable final class AppearanceThemeColors: Sendable {
    static let shared = AppearanceThemeColors()
    enum Role: Sendable {
        case text, selection, background, backgroundSecondary
    }

    private struct Palette: Sendable {
        let background: NSColor
        let backgroundSecondary: NSColor
        let text: NSColor
        let selection: NSColor

        init?(_ theme: RaycastTheme) {
            guard theme.isValid else { return nil }
            background = Self.color(theme.colors[0])
            backgroundSecondary = Self.color(theme.colors[1])
            text = Self.color(theme.colors[2])
            selection = Self.color(theme.colors[3])
        }

        private static func color(_ hex: String) -> NSColor {
            let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
    }

    private struct State: Sendable {
        var light: Palette?
        var dark: Palette?
        var preview: Palette?
        var previewSlot: RaycastTheme.Appearance?
        var opacity = AppearanceStore.defaultOpacity
        var revision = 0

        func palette(dark isDark: Bool) -> Palette? {
            if previewSlot == (isDark ? .dark : .light) { return preview }
            return isDark ? dark : light
        }
    }

    private let state = Mutex(State())

    var revision: Int {
        access(keyPath: \.revision)
        return state.withLock { $0.revision }
    }

    var hasPalette: Bool {
        _ = revision
        return state.withLock { $0.light != nil || $0.dark != nil || $0.preview != nil }
    }

    @MainActor
    func update(
        light: RaycastTheme?, dark: RaycastTheme?, preview: RaycastThemeLink.Target?, opacity: Double
    ) {
        let next = State(
            light: light.flatMap(Palette.init), dark: dark.flatMap(Palette.init),
            preview: preview?.theme.flatMap(Palette.init), previewSlot: preview?.appearance, opacity: opacity)
        withMutation(keyPath: \.revision) {
            state.withLock {
                let revision = $0.revision &+ 1
                $0 = next
                $0.revision = revision
            }
        }
    }

    func ink(_ role: Role, in appearance: NSAppearance, dark: Double, light: Double) -> NSColor? {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return state.withLock { state in
            guard let palette = state.palette(dark: isDark) else { return nil }
            switch role {
            case .text: return palette.text.withAlphaComponent(isDark ? dark : light)
            case .selection: return palette.selection.withAlphaComponent(isDark ? dark : light)
            case .background: return palette.background.withAlphaComponent(state.opacity)
            case .backgroundSecondary: return palette.backgroundSecondary.withAlphaComponent(state.opacity)
            }
        }
    }

    func dynamicColor(_ role: Role, dark: Double, light: Double, fallback: NSColor) -> NSColor {
        NSColor(name: nil) { [self] appearance in
            ink(role, in: appearance, dark: dark, light: light) ?? fallback
        }
    }
}
