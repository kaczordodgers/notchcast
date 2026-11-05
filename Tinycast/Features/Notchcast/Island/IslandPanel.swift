import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    let hardwareNotch: CGRect?
    private let screenFrame: CGRect
    var displayFrame: CGRect { screenFrame }
    var closedContext: IslandClosedContext {
        IslandClosedContext(screen: screenFrame, hardwareNotch: hardwareNotch,
                            pill: IslandGeometry.monitorPill(screen: screenFrame, size: NotchcastTheme.monitorPill))
    }
    private let surface: IslandSurfaceView
    private var open = false
    /// The launcher grown from the island: its frame while the palette is up, nil otherwise.
    private(set) var launcherFrame: CGRect?
    private var contentHeight = NotchcastTheme.estimatedContentHeight
    private var compactWidth: CGFloat = 0
    private var message: IslandMessage?
    private var closed = IslandClosedState()
    private var expandedContent = AnyView(EmptyView())
    private var headerContent = AnyView(EmptyView())
    var onOpen: (() -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    var onFocus: ((Bool) -> Void)?
    var containsPointer: Bool {
        surface.containsIsland(surface.convert(convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }

    convenience init(screen: NSScreen) {
        self.init(screenFrame: screen.frame, hardwareNotch: IslandGeometry.notchRect(
            screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea))
    }

    init(screenFrame: CGRect, hardwareNotch: CGRect?) {
        self.screenFrame = screenFrame
        self.hardwareNotch = hardwareNotch
        let canvas = IslandGeometry.openFrame(
            screen: screenFrame, centerX: hardwareNotch?.midX ?? screenFrame.midX,
            minimumWidth: NotchcastTheme.openMinimumWidth,
            contentHeight: NotchcastTheme.maximumHeight, headerHeight: hardwareNotch?.height ?? 0,
            maximumHeight: NotchcastTheme.maximumHeight + (hardwareNotch?.height ?? 0))
        surface = IslandSurfaceView(frame: CGRect(origin: .zero, size: canvas.size))
        super.init(contentRect: canvas, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isRestorable = false
        animationBehavior = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = surface
        surface.onOpen = { [weak self] in self?.onOpen?() }
        surface.onAnimationFrame = { [weak self] in
            self?.updateMousePassthrough()
            self?.invalidateShadow()
        }
    }

    override var canBecomeKey: Bool { open }
    override var canBecomeMain: Bool { false }

    override func becomeKey() {
        super.becomeKey()
        onFocus?(true)
    }

    override func resignKey() {
        super.resignKey()
        onFocus?(false)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        if event.type == .leftMouseDown, containsPointer {
            if !open, launcherFrame == nil, message?.onCancel == nil { onOpen?(); return }
            if open { makeKey() }
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    func setContent(open: AnyView, closed: IslandClosedState, header: AnyView) {
        self.closed = closed
        expandedContent = open
        headerContent = header
        let expanded = IslandContentView(content: open, header: header, headerHeight: headerHeight) { [weak self] height in
            guard let self else { return }
            let height = max(0, height.rounded(.up))
            guard contentHeight != height else { return }
            contentHeight = height
            if self.open { present(animated: true) }
        }
        let compact = IslandClosedView(context: closedContext, state: closed, cameraWidth: hardwareNotch?.width ?? 0,
                                       bandHeight: hardwareNotch?.height ?? NotchcastTheme.rowHeight,
                                       message: message) { [weak self] width in
            guard let self else { return }
            let width = max(0, width.rounded(.up))
            guard compactWidth != width else { return }
            compactWidth = width
            if !self.open, launcherFrame == nil { present(animated: true) }
        }
        surface.setContent(open: AnyView(expanded), closed: AnyView(compact
            .environment(\.hasHardwareNotch, closedContext.hasHardwareNotch)))
        present(animated: true)
    }

    func setMessage(_ message: IslandMessage?) {
        self.message = message
        setContent(open: expandedContent, closed: closed, header: headerContent)
    }

    func setActivityAccessibility(_ activity: IslandActivity?) {
        surface.setAccessibilityValue(message?.text ?? activity?.title)
    }

    func setOpen(_ open: Bool, animated: Bool) {
        self.open = open
        if !open && isKeyWindow {
            orderOut(nil)
            orderFrontRegardless()
        }
        present(animated: animated)
    }

    /// Grows the black into the launcher's frame, or shrinks it back; the palette draws over it meanwhile. On a
    /// monitor the black then fades out under the palette's glass; beside a notch it stays, as the notch is black.
    func setLauncher(height: CGFloat?, animated: Bool) {
        launcherFrame = height.map { launcherFrame(height: $0) }
        present(animated: animated)
        let fades = hardwareNotch == nil
        surface.setSurfaceOpacity(launcherFrame != nil && fades ? 0 : 1,
                                  duration: animated ? Motion.duration(launcherFrame != nil
                                      ? NotchcastTheme.Motion.launcherEnter : NotchcastTheme.Motion.launcherExit) : 0)
    }

    /// Where the palette sits over the grown island: the row under a camera, else the island's own top.
    func launcherFrame(height: CGFloat) -> CGRect {
        let width = min(screenFrame.width, NotchcastTheme.Launcher.size.width)
        let top = hardwareNotch?.minY ?? (screenFrame.maxY - NotchcastTheme.Pill.topGap)
        let x = min(max(screenFrame.minX, (hardwareNotch?.midX ?? screenFrame.midX) - width / 2), screenFrame.maxX - width)
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    /// One frame of the opening, for a still picture: the silhouette between the closed outline and the launcher's.
    func presentOpening(progress: CGFloat, height: CGFloat) {
        let from = outline
        launcherFrame = launcherFrame(height: height)
        let to = outline
        launcherFrame = nil
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
        let rect = CGRect(x: mix(from.rect.minX, to.rect.minX), y: mix(from.rect.minY, to.rect.minY),
                          width: mix(from.rect.width, to.rect.width), height: mix(from.rect.height, to.rect.height))
        let between = IslandSurfaceView.Outline(
            rect: rect, shoulder: mix(from.shoulder, to.shoulder), radius: mix(from.radius, to.radius),
            topRadius: mix(from.topRadius, to.topRadius), bubble: mix(from.bubble, to.bubble), bubbleGap: from.bubbleGap)
        surface.present(between, content: .launcher, motion: .instant)
        invalidateShadow()
    }

    func setFullScreenEnabled(_ enabled: Bool) {
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        if enabled { behavior.insert(.fullScreenAuxiliary) }
        collectionBehavior = behavior
    }

    func updateMousePassthrough() {
        let point = surface.convert(convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        ignoresMouseEvents = !isVisible || launcherFrame != nil || !surface.containsIsland(point)
    }

    override func close() {
        surface.stop()
        super.close()
    }

    var headerHeight: CGFloat { hardwareNotch?.height ?? NotchcastTheme.monitorHeader }

    private func present(animated: Bool) {
        let motion = IslandMotion.choice(
            opening: open || launcherFrame != nil, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            animationsEnabled: animated && Motion.duration(1) > 0)
        surface.present(outline, content: launcherFrame != nil ? .launcher : (open ? .open : .closed), motion: motion)
        invalidateShadow()
    }

    private func local(_ target: CGRect) -> CGRect {
        CGRect(x: target.minX - frame.minX, y: target.minY - frame.minY, width: target.width, height: target.height)
    }

    /// The silhouette for the current mode (rules.md, Shapes).
    var outline: IslandSurfaceView.Outline {
        if let launcherFrame {
            let body = hardwareNotch.map { CGRect(x: launcherFrame.minX, y: launcherFrame.minY, width: launcherFrame.width,
                                                  height: launcherFrame.height + $0.height) } ?? launcherFrame
            return .init(rect: local(body), shoulder: hardwareNotch == nil ? 0 : NotchcastTheme.openShoulder,
                         radius: NotchcastTheme.openRadius, topRadius: NotchcastTheme.openRadius)
        }
        if open {
            return .init(rect: local(openFrame), shoulder: hardwareNotch == nil ? 0 : NotchcastTheme.openShoulder,
                         radius: NotchcastTheme.openRadius, topRadius: NotchcastTheme.openRadius)
        }
        guard hardwareNotch != nil else {
            return .init(rect: local(closedFrame), radius: NotchcastTheme.statusRadius,
                         topRadius: NotchcastTheme.statusRadius,
                         bubble: message == nil && closed.hasSecond ? NotchcastTheme.Pill.bubble : 0,
                         bubbleGap: NotchcastTheme.Pill.bubbleGap)
        }
        return .init(rect: local(closedFrame), shoulder: NotchcastTheme.closedShoulder,
                     radius: hasExtraRow ? NotchcastTheme.statusRadius : NotchcastTheme.closedRadius)
    }

    /// A row under the camera: a message, a card's button, or a second thing behind the primary.
    private var hasExtraRow: Bool { message != nil || closed.needsRow }

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
                              height: NotchcastTheme.rowHeight)
            let glued = IslandGeometry.monitorPill(screen: screenFrame, size: size)
            return glued.offsetBy(dx: 0, dy: -NotchcastTheme.Pill.topGap)
        }
        let wings = !closed.isEmpty || message != nil ? max(NotchcastTheme.minimumWing * 2,
                                                             compactWidth - hardwareNotch.width) : 0
        let width = min(frame.width, hardwareNotch.width + wings + NotchcastTheme.closedShoulder * 2)
        let extra = hasExtraRow ? NotchcastTheme.rowHeight : 0
        return CGRect(x: hardwareNotch.midX - width / 2, y: hardwareNotch.minY - extra,
                      width: width, height: hardwareNotch.height + extra)
    }
}
