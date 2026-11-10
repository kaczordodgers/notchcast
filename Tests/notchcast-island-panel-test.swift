// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandPanel.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandSurfaceView.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandSilhouette.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandMotion.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandGeometry.swift
// notchcast-sources: Tinycast/DesignSystem/Interaction/Motion.swift
import AppKit
import SwiftUI

enum NotchcastTheme {
    static let openMinimumWidth: CGFloat = 800
    static let estimatedContentHeight: CGFloat = 96
    static let monitorHeader: CGFloat = 40
    static let maximumHeight: CGFloat = 475
    static let openRadius: CGFloat = 26
    static let openShoulder: CGFloat = 8
    enum Colors {
        static let surfaceInk = NSColor.black
    }
    enum Corners {
        static func bottomRadius(height: CGFloat) -> CGFloat { height / 3 }
    }
    enum Closed {
        static let row: CGFloat = 36
        static let topGap: CGFloat = 4
        static let idleWidth: CGFloat = 144
        static let bubbleGap: CGFloat = 12
        static let shoulder: CGFloat = 6
    }
    enum Opening {
        static let dissolve: TimeInterval = 0.12
        static let dissolveDelay: TimeInterval = 0.3
        static let returnFade: TimeInterval = 0.18
    }
    @MainActor enum Launcher {
        static var size = CGSize(width: 750, height: 475)
        static let radius: CGFloat = 26
        static var canvasWidth: CGFloat { max(openMinimumWidth, size.width + openShoulder * 2) }
    }
}

struct IslandMessage {
    let onCancel: (() -> Void)?
}

enum IslandClosedItem {
    case message(IslandMessage)
    case card
}

struct IslandClosedState {
    var main: IslandClosedItem?
    var second: IslandClosedItem?
    static var idle: Self { Self() }
    var isIdle: Bool { main == nil }
    var spokenSummary: String? { nil }
    var key: String { isIdle ? "idle" : "active" }
}

extension EnvironmentValues {
    @Entry var hasHardwareNotch = false
}

struct IslandContentView: View {
    var content: AnyView
    var header: AnyView
    var headerHeight: CGFloat
    var onHeight: (CGFloat) -> Void
    var body: some View { content }
}

struct IslandClosedView: View {
    var hardwareNotch: CGRect?
    var state: IslandClosedState
    var onSize: (CGSize) -> Void
    var onButtonFrame: (CGRect) -> Void = { _ in }
    var body: some View { Color.clear }
}

/// The launcher scales with the interface size while the app runs; the canvas it grows inside must follow, and the
/// island on screen must not move when it does.
@main
@MainActor
struct IslandPanelTests {
    static func main() {
        Motion.isEnabled = false
        for notch in [CGRect(x: 656, y: 950, width: 200, height: 32), nil] {
            followsInterfaceSize(notch: notch)
            cardClicks(notch: notch)
            pointerReachesController(notch: notch)
        }
        print("notchcast-island-panel: the canvas follows the interface size; the island stays where it was")
    }

    static func cardClicks(notch: CGRect?) {
        let panel = IslandPanel(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), hardwareNotch: notch)
        panel.setContent(open: AnyView(EmptyView()), closed: .init(main: .card), header: AnyView(EmptyView()))
        panel.cardButtonFrame = CGRect(x: 400, y: 40, width: 60, height: 28)
        let height = panel.contentView!.bounds.height
        assert(panel.cardTakesClick(at: CGPoint(x: 430, y: height - 54)), "the action keeps its click")
        assert(!panel.cardTakesClick(at: CGPoint(x: 300, y: height - 54)), "the title opens the island")
        assert(!panel.cardTakesClick(at: CGPoint(x: 280, y: height - 54)), "the glyph opens the island")
        panel.setClosedState(.idle)
        assert(!panel.cardTakesClick(at: CGPoint(x: 430, y: height - 54)), "an old action frame is inactive")
        panel.close()
    }

    /// Over the island the panel takes the pointer from the global monitor, and a non-key panel in an inactive app
    /// gets mouse-moved events only through an always-active tracking area; leaving must still reach the controller.
    static func pointerReachesController(notch: CGRect?) {
        let panel = IslandPanel(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), hardwareNotch: notch)
        let surface = panel.contentView!
        let tracking: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        precondition(surface.trackingAreas.contains { $0.options.isSuperset(of: tracking) },
                     "the surface tracks the pointer while the app is inactive")
        var seen: [NSEvent.EventType] = []
        panel.onPointer = { seen.append($0.type) }
        surface.mouseMoved(with: NSEvent.mouseEvent(
            with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!)
        surface.mouseExited(with: NSEvent.enterExitEvent(
            with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!)
        precondition(seen == [.mouseMoved, .mouseExited], "moving and leaving reach the controller")
        panel.close()
    }

    static func followsInterfaceSize(notch: CGRect?) {
        let standard = CGSize(width: 750, height: 475)
        NotchcastTheme.Launcher.size = standard
        let panel = IslandPanel(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), hardwareNotch: notch)
        panel.setContent(open: AnyView(EmptyView()), closed: .idle, header: AnyView(EmptyView()))
        let launched = panel.frame
        let island = shape(panel)
        assert(panel.frame.contains(launcher(under: panel)))

        NotchcastTheme.Launcher.size = CGSize(width: 900, height: 570)
        assert(!panel.frame.contains(launcher(under: panel)), "the launch-time canvas clips a Larger launcher")
        panel.fitCanvas()
        assert(panel.frame.contains(launcher(under: panel)), "the canvas grows with the interface size")
        assert(panel.contentView?.frame.size == panel.frame.size, "the surface fills the grown canvas")
        assert(shape(panel) == island, "the island stays put while its canvas grows")

        NotchcastTheme.Launcher.size = standard
        panel.fitCanvas()
        assert(panel.frame == launched, "back at Standard the canvas is the launch-time one again")
        assert(shape(panel) == island)
        panel.close()
    }

    /// The expanded launcher's black: centred on the closed body, its top under the notch or level with the pill, with
    /// the shoulders it hangs from the screen's top by.
    static func launcher(under panel: IslandPanel) -> CGRect {
        let body = panel.closedBodyFrame
        let size = NotchcastTheme.Launcher.size
        let top = panel.hardwareNotch?.minY ?? body.maxY
        return CGRect(x: body.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
            .insetBy(dx: -NotchcastTheme.openShoulder, dy: 0)
    }

    /// The drawn silhouette in screen space.
    static func shape(_ panel: IslandPanel) -> CGRect {
        guard let path = (panel.contentView?.layer?.mask as? CAShapeLayer)?.path else { fatalError("no silhouette") }
        return path.boundingBox.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
    }
}
