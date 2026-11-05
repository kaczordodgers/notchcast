import AppKit
import SwiftUI

final class IslandPanel: NSPanel {
    let hardwareNotch: CGRect?
    private let screenFrame: CGRect
    var displayFrame: CGRect { screenFrame }
    private let surface: IslandSurfaceView
    private var open = false
    private var contentHeight = NotchcastTheme.estimatedContentHeight
    private var closedSize = CGSize.zero
    private var state = IslandClosedState.idle
    private var expandedContent = AnyView(EmptyView())
    private var headerContent = AnyView(EmptyView())
    /// The launcher this island grew into, while it is up.
    private(set) var launcherFrame: CGRect?
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
            contentHeight: Self.canvasHeight(hardwareNotch), headerHeight: 0,
            maximumHeight: Self.canvasHeight(hardwareNotch))
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

    /// Tall enough for the launcher to grow inside it: the closed band, the launcher's gap and the launcher.
    static func canvasHeight(_ notch: CGRect?) -> CGFloat {
        let band = notch?.height ?? NotchcastTheme.Closed.topGap + NotchcastTheme.Closed.row
        return max(NotchcastTheme.maximumHeight, band + NotchcastTheme.Launcher.gap + NotchcastTheme.Launcher.size.height)
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
            if !open, !hasCancellableMessage, !hasCard { onOpen?(); return }
            if open { makeKey() }
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    private var hasCancellableMessage: Bool {
        if case .message(let message) = state.main { return message.onCancel != nil }
        return false
    }

    /// A card's button takes the click; the rest of a card still opens the island.
    private var hasCard: Bool {
        guard case .card = state.main else { return false }
        return surface.hitTest(surface.convert(convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)) !== surface
    }

    func setContent(open: AnyView, closed: IslandClosedState, header: AnyView) {
        state = closed
        expandedContent = open
        headerContent = header
        let expanded = IslandContentView(content: open, header: header, headerHeight: headerHeight) { [weak self] height in
            guard let self else { return }
            let height = max(0, height.rounded(.up))
            guard contentHeight != height else { return }
            contentHeight = height
            if self.open { present(animated: true) }
        }
        let compact = IslandClosedView(hardwareNotch: hardwareNotch, state: closed) { [weak self] size in
            guard let self else { return }
            let size = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
            guard closedSize != size else { return }
            closedSize = size
            if !self.open { present(animated: true) }
        }
        surface.setContent(open: AnyView(expanded), closed: AnyView(compact
            .environment(\.hasHardwareNotch, hardwareNotch != nil)))
        surface.setAccessibilityValue(closed.spokenSummary)
        present(animated: true)
    }

    func setClosedState(_ closed: IslandClosedState) {
        setContent(open: expandedContent, closed: closed, header: headerContent)
    }

    func setOpen(_ open: Bool, animated: Bool) {
        self.open = open
        if !open && isKeyWindow {
            orderOut(nil)
            orderFrontRegardless()
        }
        present(animated: animated)
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

    // MARK: The opening into the launcher

    /// The black island grows into the launcher's frame, then dissolves onto the glass launcher shown there.
    func growIntoLauncher(_ launcher: CGRect) {
        guard launcherFrame == nil, isVisible, !open else { return }
        launcherFrame = launcher
        let motion = morphMotion(animated: true)
        surface.present(outline: local(Self.launcherOutline(launcher)), openRect: local(openFrame),
                        showing: .none, motion: motion == .open ? .open : .instant)
        updateMousePassthrough()
        let grow = motion == .open ? NotchcastTheme.Opening.grow : 0
        let dissolve = Motion.duration(NotchcastTheme.Opening.dissolve)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(grow))
            guard let self, launcherFrame == launcher else { return }
            surface.setVisible(false, duration: dissolve)
            try? await Task.sleep(for: .seconds(dissolve))
            guard launcherFrame == launcher else { return }
            surface.present(outline: local(closedOutline), openRect: local(openFrame), showing: .closed,
                            motion: .instant)
        }
    }

    /// The launcher has gone: the island comes back at rest.
    func launcherDidClose() {
        guard launcherFrame != nil else { return }
        launcherFrame = nil
        present(animated: false)
        surface.setVisible(true, duration: Motion.duration(NotchcastTheme.Opening.returnFade))
        updateMousePassthrough()
    }

    /// The gallery's still frames of the opening, at `progress` from closed (0) to the launcher (1).
    func showOpening(into launcher: CGRect, progress: CGFloat) {
        let outline = IslandOutline.interpolate(closedOutline, Self.launcherOutline(launcher), progress: progress)
        surface.present(outline: local(outline), openRect: local(openFrame),
                        showing: progress == 0 ? .closed : .none, motion: .instant)
    }

    /// The launcher's own outline: the compact bar is a capsule, the expanded palette rounds at `panel`.
    static func launcherOutline(_ launcher: CGRect) -> IslandOutline {
        let radius = launcher.height < NotchcastTheme.Launcher.size.height
            ? launcher.height / 2 : NotchcastTheme.Launcher.radius
        return IslandOutline(body: launcher, bottomRadius: radius, topRadius: radius)
    }

    /// The closed body in screen space, where the launcher hangs from.
    var closedBodyFrame: CGRect { closedOutline.body }

    // MARK: Presenting

    private func present(animated: Bool) {
        guard launcherFrame == nil else { return }
        let outline = open ? openOutline : closedOutline
        surface.present(outline: local(outline), openRect: local(openFrame), showing: open ? .open : .closed,
                        motion: morphMotion(animated: animated))
        invalidateShadow()
    }

    private func morphMotion(animated: Bool) -> IslandMotion {
        IslandMotion.choice(
            opening: open || launcherFrame != nil,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            animationsEnabled: animated && Motion.duration(1) > 0)
    }

    private func local(_ outline: IslandOutline) -> IslandOutline {
        var outline = outline
        outline.body = local(outline.body)
        outline.bubble = outline.bubble.map(local)
        return outline
    }

    private func local(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX - frame.minX, y: rect.minY - frame.minY, width: rect.width, height: rect.height)
    }

    private var openOutline: IslandOutline {
        IslandOutline(body: openFrame, shoulder: hardwareNotch == nil ? 0 : NotchcastTheme.openShoulder,
                      bottomRadius: NotchcastTheme.openRadius)
    }

    private var openFrame: CGRect {
        IslandGeometry.openFrame(
            screen: screenFrame, centerX: hardwareNotch?.midX ?? screenFrame.midX,
            minimumWidth: NotchcastTheme.openMinimumWidth,
            contentHeight: contentHeight, headerHeight: headerHeight,
            maximumHeight: NotchcastTheme.maximumHeight)
    }

    /// Notch: exactly the cutout at rest, else the measured body hung from the top edge. Monitor: a pill under the
    /// top edge, and the bubble beside it for a second thing.
    private var closedOutline: IslandOutline {
        if let notch = hardwareNotch {
            guard !state.isIdle else {
                return IslandOutline(body: notch, bottomRadius: NotchcastTheme.Corners.bottomRadius(height: notch.height))
            }
            let size = CGSize(width: max(notch.width, closedSize.width), height: max(notch.height, closedSize.height))
            return IslandOutline(
                body: CGRect(x: notch.midX - size.width / 2, y: notch.maxY - size.height,
                             width: size.width, height: size.height),
                shoulder: NotchcastTheme.Closed.shoulder,
                bottomRadius: NotchcastTheme.Corners.bottomRadius(height: size.height))
        }
        let row = NotchcastTheme.Closed.row
        let pill = IslandGeometry.monitorPill(
            screen: screenFrame, size: CGSize(width: max(NotchcastTheme.Closed.idleWidth, closedSize.width), height: row),
            topGap: NotchcastTheme.Closed.topGap)
        let bubble = state.second == nil ? nil
            : CGRect(x: pill.maxX + NotchcastTheme.Closed.bubbleGap, y: pill.minY, width: row, height: row)
        return IslandOutline(body: pill, bottomRadius: row / 2, topRadius: row / 2, bubble: bubble)
    }
}
