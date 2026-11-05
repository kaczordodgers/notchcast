import AppKit

extension IslandPanel {
    /// The closed body the launcher hangs from; the bubble beside a monitor pill never moves it.
    var launcherPlacementFrame: CGRect? {
        guard isVisible, isOnActiveSpace else { return nil }
        return closedBodyFrame
    }
}
