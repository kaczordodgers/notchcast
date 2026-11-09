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
    var cardButtonFrame = CGRect.zero
    private var expandedContent = AnyView(EmptyView())
    private var headerContent = AnyView(EmptyView())
    /// The launcher this island grew into, while it is up.
    private(set) var launcherFrame: CGRect?
    /// Where the silhouette is heading, in screen space; a closed change morphs from it.
    private var shownOutline: IslandOutline?
    var onOpen: (() -> Void)?
    var onKey: ((NSEvent) -> Bool)?
    var onFocus: ((Bool) -> Void)?
    var onPointer: ((NSEvent) -> Void)?
    /// False while the launcher hides the island, so hovering its empty spot never opens it.
    var containsPointer: Bool {
        launcherFrame == nil
            && surface.containsIsland(surface.convert(convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }

    convenience init(screen: NSScreen) {
        #if DEBUG
        if let notch = NotchcastLiveDemo.simulatedNotch(on: screen) {
            self.init(screenFrame: screen.frame, hardwareNotch: notch)
            return
        }
        #endif
        self.init(screenFrame: screen.frame, hardwareNotch: IslandGeometry.notchRect(
            screen: screen.frame, safeAreaTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea))
    }

    init(screenFrame: CGRect, hardwareNotch: CGRect?) {
        self.screenFrame = screenFrame
        self.hardwareNotch = hardwareNotch
        let canvas = Self.canvasFrame(screen: screenFrame, notch: hardwareNotch)
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
        surface.onPointer = { [weak self] in self?.onPointer?($0) }
        surface.onAnimationFrame = { [weak self] in
            self?.updateMousePassthrough()
            self?.invalidateShadow()
        }
    }

    /// Tall enough for the launcher to grow inside it: the notch's band (or the pill's gap) and the launcher.
    static func canvasHeight(_ notch: CGRect?) -> CGFloat {
        let band = notch?.height ?? NotchcastTheme.Closed.topGap
        return max(NotchcastTheme.maximumHeight, band + NotchcastTheme.Launcher.size.height)
    }

    /// The panel's frame at the current interface size.
    static func canvasFrame(screen: CGRect, notch: CGRect?) -> CGRect {
        IslandGeometry.openFrame(
            screen: screen, centerX: notch?.midX ?? screen.midX, minimumWidth: NotchcastTheme.Launcher.canvasWidth,
            contentHeight: canvasHeight(notch), headerHeight: 0, maximumHeight: canvasHeight(notch))
    }

    /// The launcher scales with the interface size, so the canvas it grows inside follows; the shape stays put.
    func fitCanvas() {
        let canvas = Self.canvasFrame(screen: screenFrame, notch: hardwareNotch)
        guard frame != canvas else { return }
        setFrame(canvas, display: false)
        if let launcherFrame {
            show(launcherOutline(launcherFrame), showing: .none, motion: .instant)
        } else {
            present(animated: false)
        }
        updateMousePassthrough()
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
        let point = surface.convert(convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return cardTakesClick(at: point)
    }

    func cardTakesClick(at point: CGPoint) -> Bool {
        guard case .card = state.main else { return false }
        return cardButtonFrame.contains(CGPoint(x: point.x, y: surface.bounds.height - point.y))
    }

    func setContent(open: AnyView, closed: IslandClosedState, header: AnyView) {
        let handover = state.key != closed.key && Motion.isEnabled
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if state.key != closed.key { cardButtonFrame = .zero }
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
        let compact = IslandClosedView(hardwareNotch: hardwareNotch, state: closed, onSize: { [weak self] size in
            guard let self else { return }
            let size = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
            guard closedSize != size else { return }
            closedSize = size
            if !self.open { present(animated: true) }
        }, onButtonFrame: { [weak self] frame in self?.cardButtonFrame = frame })
        surface.setContent(open: AnyView(expanded), closed: AnyView(compact
            .environment(\.hasHardwareNotch, hardwareNotch != nil)), handover: handover)
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
        guard collectionBehavior != behavior else { return }
        collectionBehavior = behavior
        if isVisible { orderFrontRegardless() }
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

    /// The black grows into the launcher and stays as its surface; the launcher's rows fade in on it once it has
    /// arrived. Reduce Motion: the island cross-fades into the launcher's shape as the rows fade in.
    func growIntoLauncher(_ launcher: CGRect, window: NSWindow) {
        // Already growing: a second key change mid-opening must not show the rows early.
        guard launcherFrame == nil else { return }
        guard isVisible, !open else {
            window.alphaValue = 1
            return
        }
        launcherFrame = launcher
        updateMousePassthrough()
        surface.setAccessibilityShown(false)
        let outline = launcherOutline(launcher)
        let motion = morphMotion(to: outline, animated: true)
        show(outline, showing: .none, motion: motion)
        switch motion {
        case .instant: window.alphaValue = 1
        case .fade: reveal(window, after: 0)
        default: reveal(window, after: NotchcastTheme.Opening.dissolveDelay)
        }
    }

    private var revealTask: Task<Void, Never>?

    /// The launcher's rows appear once the black is nearly in place (`Opening.handoff`), over `Opening.dissolve`.
    private func reveal(_ window: NSWindow, after delay: TimeInterval) {
        revealTask?.cancel()
        revealTask = Task { @MainActor [weak window] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let window, window.isVisible else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = NotchcastTheme.Opening.dissolve
                window.animator().alphaValue = 1
            }, completionHandler: nil)
        }
    }

    /// The launcher has gone: the black shrinks back from wherever it is to the island at rest, or opens if it was
    /// asked to meanwhile.
    func launcherDidClose() {
        guard launcherFrame != nil else { return }
        launcherFrame = nil
        revealTask?.cancel()
        revealTask = nil
        if !surface.isShown { show(closedOutline, showing: .closed, motion: .instant) }
        present(animated: true)
        surface.setVisible(true, duration: Motion.duration(NotchcastTheme.Opening.returnFade))
        updateMousePassthrough()
    }

    /// The gallery's still frames of the opening, at `progress` from closed (0) to the launcher (1).
    func showOpening(into launcher: CGRect, progress: CGFloat) {
        let outline = IslandOutline.interpolate(closedOutline, launcherOutline(launcher), progress: progress)
        show(outline, showing: progress == 0 ? .closed : .none, motion: .instant)
    }

    /// The launcher's outline as part of the island. Under a notch the black runs up to the top edge and meets it
    /// with the open island's shoulders; on a monitor it is the palette's own rounded frame, grown from the pill.
    func launcherOutline(_ launcher: CGRect) -> IslandOutline {
        Self.launcherOutline(launcher, notch: hardwareNotch != nil, screenTop: screenFrame.maxY)
    }

    static func launcherOutline(_ launcher: CGRect, notch: Bool, screenTop: CGFloat) -> IslandOutline {
        let radius = launcher.height < NotchcastTheme.Launcher.size.height
            ? launcher.height / 2 : NotchcastTheme.Launcher.radius
        guard notch else { return IslandOutline(body: launcher, bottomRadius: radius, topRadius: radius) }
        let shoulder = NotchcastTheme.openShoulder
        let body = CGRect(x: launcher.minX - shoulder, y: launcher.minY, width: launcher.width + shoulder * 2,
                          height: screenTop - launcher.minY)
        return IslandOutline(body: body, shoulder: shoulder, bottomRadius: radius)
    }

    /// The closed body in screen space, where the launcher hangs from.
    var closedBodyFrame: CGRect { closedOutline.body }

    /// The open body in screen space, which a launcher must not sit under.
    var openBodyFrame: CGRect { openFrame }

    // MARK: Presenting

    private func present(animated: Bool) {
        guard launcherFrame == nil else { return }
        let outline = open ? openOutline : closedOutline
        show(outline, showing: open ? .open : .closed, motion: morphMotion(to: outline, animated: animated))
    }

    private func show(_ outline: IslandOutline, showing: IslandSurfaceView.Showing, motion: IslandMotion) {
        surface.present(outline: local(outline), openRect: local(openFrame), showing: showing, motion: motion)
        shownOutline = outline
        invalidateShadow()
    }

    private func morphMotion(to outline: IslandOutline, animated: Bool) -> IslandMotion {
        IslandMotion.choice(
            from: shownOutline, to: outline, opening: open || launcherFrame != nil,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            animationsEnabled: animated && Motion.isEnabled)
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
                return IslandOutline(body: notch.insetBy(dx: -NotchcastTheme.Closed.shoulder, dy: 0),
                                     shoulder: NotchcastTheme.Closed.shoulder,
                                     bottomRadius: NotchcastTheme.Corners.bottomRadius(height: notch.height))
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
