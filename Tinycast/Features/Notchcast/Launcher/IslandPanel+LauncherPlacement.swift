import AppKit

extension IslandPanel {
    /// Where a launcher hangs from this island: the closed body's width, ending at the launcher's top edge (the
    /// notch's bottom, or the monitor pill's top). The bubble beside a monitor pill never moves it.
    var launcherAttachment: CGRect? {
        guard isVisible, isOnActiveSpace else { return nil }
        let body = closedBodyFrame
        let top = hardwareNotch?.minY ?? body.maxY
        return CGRect(x: body.minX, y: top, width: body.width, height: 0)
    }
}
