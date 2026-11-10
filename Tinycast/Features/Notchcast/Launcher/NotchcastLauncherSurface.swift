import AppKit

@MainActor
enum NotchcastLauncherSurface {
    #if DEBUG
    /// The live demo picks the display; the palette otherwise opens where Tinycast's own setting puts it.
    static var preferredScreen: NSScreen?
    #else
    static var preferredScreen: NSScreen? { nil }
    #endif
}
