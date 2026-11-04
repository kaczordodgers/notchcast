import AppKit
import QuartzCore

extension IslandPanel {
    var launcherPlacementFrame: CGRect? {
        guard isVisible, isOnActiveSpace,
              let surface = contentView,
              let silhouette = surface.layer?.mask as? CAShapeLayer,
              let path = silhouette.presentation()?.path ?? silhouette.path else { return nil }
        return convertToScreen(surface.convert(path.boundingBoxOfPath, to: nil))
    }
}
