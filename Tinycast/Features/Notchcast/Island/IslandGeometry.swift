import Foundation

struct IslandClosedContext: Sendable {
    let screen: CGRect
    let hardwareNotch: CGRect?
    let pill: CGRect
    var hasHardwareNotch: Bool { hardwareNotch != nil }

    func wingWidth(contentWidth: CGFloat, minimum: CGFloat) -> CGFloat {
        hasHardwareNotch ? max(minimum, contentWidth) : contentWidth
    }
}

enum IslandGeometry {
    static func screenIndex(containing point: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }

    static func notchRect(
        screen: CGRect, safeAreaTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?
    ) -> CGRect? {
        guard safeAreaTop > 0, safeAreaTop <= screen.height,
              let leftArea, let rightArea,
              leftArea.minX >= screen.minX, rightArea.maxX <= screen.maxX,
              leftArea.maxX > screen.minX, rightArea.minX < screen.maxX,
              rightArea.minX > leftArea.maxX else { return nil }
        return CGRect(
            x: leftArea.maxX, y: screen.maxY - safeAreaTop,
            width: rightArea.minX - leftArea.maxX, height: safeAreaTop)
    }

    static func monitorPill(screen: CGRect, size: CGSize) -> CGRect {
        let width = min(max(0, size.width), screen.width)
        let height = min(max(0, size.height), screen.height)
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - height,
                      width: width, height: height)
    }

    static func openFrame(
        screen: CGRect, centerX: CGFloat, minimumWidth: CGFloat,
        contentHeight: CGFloat, headerHeight: CGFloat, maximumHeight: CGFloat
    ) -> CGRect {
        let width = min(screen.width, max(0, minimumWidth))
        let header = min(screen.height, max(0, headerHeight))
        let height = min(screen.height, max(header, min(maximumHeight, header + max(0, contentHeight))))
        let originX = min(max(screen.minX, centerX - width / 2), screen.maxX - width)
        return CGRect(x: originX, y: screen.maxY - height, width: width, height: height)
    }
}
