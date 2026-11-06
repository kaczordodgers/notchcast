import AppKit
import Observation

/// The launcher hung from the island is part of it: the island's black is its surface, so the palette drops its
/// glass for black, takes dark ink, sits just above the island and stays invisible until the black has arrived.
@MainActor
@Observable
final class NotchcastLauncherSurface {
    static let shared = NotchcastLauncherSurface()
    private(set) var attached = false
    /// One level above the island (`statusBar + 1`), so the launcher's rows draw over its black.
    static let level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)

    #if DEBUG
    /// The live demo picks the display; the palette otherwise opens where Tinycast's own setting puts it.
    static var preferredScreen: NSScreen?
    #else
    static var preferredScreen: NSScreen? { nil }
    #endif

    private var palette: NSPanel? { NSApp.windows.first { $0 is PalettePanel } as? NSPanel }

    func prepare(attached: Bool) {
        self.attached = attached
        AppearanceIslandBackdrop.shared.attached = attached
        guard let palette else { return }
        palette.appearance = attached ? NSAppearance(named: .darkAqua) : nil
        palette.hasShadow = !attached
        palette.animationBehavior = attached || !Motion.isEnabled ? .none : .documentWindow
        if attached { palette.level = Self.level }
        // A re-anchor while up (a new interface size) must not blank a launcher already shown.
        if !palette.isVisible { palette.alphaValue = attached ? 0 : 1 }
    }

    /// Tinycast puts the palette back at its own level each time it takes key, from a delegate that may run after
    /// this observer, so the attached one goes back above the island on the next turn as well.
    func keepAbove(_ palette: NSWindow) {
        guard attached else { return }
        palette.level = Self.level
        DispatchQueue.main.async { [weak self, weak palette] in
            guard let self, self.attached, let palette, palette.isVisible else { return }
            palette.level = Self.level
        }
    }
}
