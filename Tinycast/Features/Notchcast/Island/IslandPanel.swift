import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    let hardwareNotch: CGRect?
    private let screenFrame: CGRect
    var displayFrame: CGRect { screenFrame }
    private let surface: IslandSurfaceView
    private var open = false
    private var contentHeight = NotchcastTheme.estimatedContentHeight
    private var compactWidth: CGFloat = 0
    private var hasCompactContent = false

    init(screen: NSScreen) {
        screenFrame = screen.frame
        hardwareNotch = IslandGeometry.notchRect(
            screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
        let canvas = IslandGeometry.openFrame(
            screen: screen.frame, centerX: hardwareNotch?.midX ?? screen.frame.midX,
            minimumWidth: NotchcastTheme.openMinimumWidth,
            contentHeight: NotchcastTheme.maximumHeight, headerHeight: 0,
            maximumHeight: NotchcastTheme.maximumHeight)
        surface = IslandSurfaceView(frame: CGRect(origin: .zero, size: canvas.size))
        super.init(contentRect: canvas, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isRestorable = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = surface
        surface.onAnimationFrame = { [weak self] in
            self?.updateMousePassthrough()
            self?.invalidateShadow()
        }
    }

    override var canBecomeKey: Bool { open }
    override var canBecomeMain: Bool { false }

    func setContent(open: AnyView, closed: IslandController.ClosedContent) {
        hasCompactContent = closed.leading != nil || closed.trailing != nil
        let expanded = IslandContentView(content: open, headerHeight: headerHeight) { [weak self] height in
            guard let self else { return }
            let height = max(0, height.rounded(.up))
            guard contentHeight != height else { return }
            contentHeight = height
            if self.open { present(animated: true) }
        }
        let compact = IslandClosedView(content: closed, cameraWidth: hardwareNotch?.width ?? 0) { [weak self] width in
            guard let self else { return }
            let width = max(0, width.rounded(.up))
            guard compactWidth != width else { return }
            compactWidth = width
            if !self.open { present(animated: true) }
        }
        surface.setContent(open: AnyView(expanded), closed: AnyView(compact))
    }

    func setOpen(_ open: Bool, animated: Bool) {
        self.open = open
        if !open && isKeyWindow { resignKey() }
        present(animated: animated)
    }

    func setFullScreenEnabled(_ enabled: Bool) {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if enabled { behavior.insert(.fullScreenAuxiliary) }
        collectionBehavior = behavior
    }

    func updateMousePassthrough() {
        let point = surface.convert(convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        ignoresMouseEvents = !isVisible || !surface.containsIsland(point)
    }

    override func close() {
        surface.stop()
        super.close()
    }

    private var headerHeight: CGFloat { hardwareNotch?.height ?? NotchcastTheme.monitorHeader }

    private func present(animated: Bool) {
        let target = open ? openFrame : closedFrame
        let rect = CGRect(x: target.minX - frame.minX, y: target.minY - frame.minY,
                          width: target.width, height: target.height)
        let shoulder = hardwareNotch == nil ? 0
            : (open ? NotchcastTheme.openShoulder : NotchcastTheme.closedShoulder)
        let motion = IslandMotion.choice(
            opening: open, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            animationsEnabled: animated && Motion.duration(1) > 0)
        surface.present(rect: rect, shoulder: shoulder,
                        radius: open ? NotchcastTheme.openRadius : NotchcastTheme.closedRadius,
                        open: open, motion: motion)
        invalidateShadow()
    }

    private var openFrame: CGRect {
        IslandGeometry.openFrame(
            screen: screenFrame, centerX: hardwareNotch?.midX ?? screenFrame.midX,
            minimumWidth: NotchcastTheme.openMinimumWidth,
            contentHeight: contentHeight, headerHeight: headerHeight,
            maximumHeight: NotchcastTheme.maximumHeight)
    }

    private var closedFrame: CGRect {
        guard let hardwareNotch else {
            let size = CGSize(width: min(frame.width, max(NotchcastTheme.monitorPill.width, compactWidth)),
                              height: NotchcastTheme.monitorPill.height)
            return IslandGeometry.monitorPill(screen: screenFrame, size: size)
        }
        let wings = hasCompactContent ? max(NotchcastTheme.minimumWing * 2,
                                           compactWidth - hardwareNotch.width) : 0
        let width = min(frame.width, hardwareNotch.width + wings + NotchcastTheme.closedShoulder * 2)
        return CGRect(x: hardwareNotch.midX - width / 2, y: hardwareNotch.minY,
                      width: width, height: hardwareNotch.height)
    }
}
