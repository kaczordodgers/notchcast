import AppKit

extension IslandPanel {
    /// The edge a launcher hangs under: the closed body's bottom, so a row grown below the notch stays uncovered.
    var launcherAttachment: CGRect? {
        guard isVisible, isOnActiveSpace else { return nil }
        let body = closedBodyFrame
        return CGRect(x: body.minX, y: body.minY, width: body.width, height: 0)
    }
}
