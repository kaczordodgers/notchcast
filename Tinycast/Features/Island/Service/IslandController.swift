import AppKit
import IslandCore
import IslandUI

@MainActor
final class IslandController: NSObject {
    let source = IslandFrameSource()
    let backdrop = IslandBackdrop()
    let canvas = IslandCanvas()
    lazy var frost = IslandFrost(canvas: canvas, backdrop: backdrop)
    private(set) var surface: IslandSurface<CGSize>?
    private var layout: IslandLayout?
    private var configuration: IslandSurfaceConfiguration?
    private var pending = IslandHold<NSScreen>()
    private(set) weak var panel: PalettePanel?
    private var observer: PanelObserver?
    private let clip = CAShapeLayer()
    /// An open island page (#975): the outline grows to its panel and masks it, as for the palette.
    weak var page: NSPanel? { didSet { page?.contentView?.layer?.mask = pageClip; frameChanged() } }
    private let pageClip = CAShapeLayer()
    let keyline = CAShapeLayer()
    private(set) var overlays: [CGRect] = []
    #if DEBUG
    private(set) var samples: [String] = []
    let frames = IslandFrameTrace()
    private var captureName: String?
    private var captureDone: CheckedContinuation<Void, Never>?
    private(set) var captured: [String] = []
    #endif
    var showsRest = true
    var outlineWhenOpen = true {
        didSet { canvas.keylineEnabled = outlineWhenOpen; if outlineWhenOpen != oldValue { paintFrame() } }
    }
    /// Read at `configure`, so a change takes effect when the coordinator reconfigures the screen.
    var position = IslandPosition.topEdge
    var openingTop: CGFloat? { layout?.openingTop }
    var notchWidth: CGFloat? { layout?.notchWidth }
    func openingX(width: CGFloat) -> CGFloat? { layout?.openingX(width: width) }
    /// AppKit's getter keeps returning `.none` once set, so it also says the window was ever hidden.
    var sharingType: NSWindow.SharingType {
        get { backdrop.sharingType }
        set { backdrop.sharingType = newValue; frost.sharingType = newValue }
    }
    /// A full-screen Space keeps only glances and attached surfaces.
    var onFullScreenSpace = false {
        didSet { if onFullScreenSpace != oldValue { frameChanged() } }
    }
    private var glancing = false
    var canOpen: (() -> Bool)?
    var onOpen: (() -> Void)? { didSet { canvas.onOpen = onOpen } }
    /// Hands over the pill's rect, top-left origin in the island window, for the pill menu.
    var onMenu: ((CGRect, NSWindow) -> Void)?
    var onSettle: (() -> Void)?
    private(set) var screen: NSScreen?
    var hasOverlays: Bool { !overlays.isEmpty }
    var isMoving: Bool { !source.isIdle }
    /// The visible outline in screen points, for the hover zone.
    var screenShape: CGRect? {
        guard let bounds = canvas.outline?.boundingBoxOfPath else { return nil }
        return bounds.offsetBy(dx: backdrop.frame.minX, dy: backdrop.frame.minY).intersection(backdrop.frame)
    }

    var glance: IslandGlance? { didSet { if glance != oldValue { redraw() } } }
    var level: IslandLevel? { didSet { if level != oldValue { redraw() } } }
    var expanded = false { didSet { if expanded != oldValue { redraw() } } }
    var notice: IslandNotice? { didSet { if notice != oldValue { redraw() } } }
    var statuses: [IslandStatus] = [] { didSet { if statuses != oldValue { redraw() } } }
    var song: IslandNowPlaying? { didSet { if song != oldValue { redraw() } } }
    /// D16: a new song grows the pill below a notch, as the meeting expansion does.
    var songChange = false { didSet { if songChange != oldValue { redraw() } } }

    private func redraw() {
        canvas.show(glance: glance, level: level, notice: notice, statuses: statuses, expanded: expanded,
                    notch: layout?.notchWidth, song: song, songChange: songChange)
        canvas.setAccessibilityValue(accessibilityValue)
        frameChanged()
    }

    override init() {
        super.init()
        backdrop.contentView = frost.root
        canvas.wantsLayer = true
        canvas.onAppearanceChange = { [weak self] in self?.paintFrame() }
        canvas.setAccessibilityElement(true)
        canvas.setAccessibilityRole(.group)
        canvas.setAccessibilityLabel(String(localized: "Notchcast", table: "Notchcast"))
        canvas.setAccessibilityValue("")
        canvas.onMenu = { [weak self] in
            guard let self, let rect = self.pillRect else { return }
            self.onMenu?(rect, self.backdrop)
        }
        canvas.canOpen = { [weak self] in
            guard let self else { return false }
            return self.canOpen?() == true && self.overlays.isEmpty && NSApp.modalWindow == nil
                && self.page == nil && (self.isResting || (self.expanded || self.songChange) && self.source.isIdle)
        }
        source.didFrame = { [weak self] in self?.paintFrame() }
        source.didSettle = { [weak self] in self?.applyPending(); self?.onSettle?() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(frameChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    func attach(_ panel: PalettePanel, screen: NSScreen) {
        guard self.panel !== panel else { return }
        self.panel = panel
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.mask = clip
        keyline.fillColor = nil
        keyline.zPosition = 1000
        panel.contentView?.layer?.addSublayer(keyline)
        panel.hasShadow = false
        observer = PanelObserver(panel: panel, changed: { [weak self] in self?.frameChanged() })
        if layout == nil { configure(screen) }
        frameChanged()
    }

    func detach() {
        observer = nil
        if panel?.contentView?.layer?.mask === clip { panel?.contentView?.layer?.mask = nil }
        keyline.removeFromSuperlayer()
        panel = nil
        closed()
    }

    /// A full-screen Space hides the menu bar without a screen-parameters change, so re-read it.
    func refreshMenuBar(_ screen: NSScreen) {
        guard let layout, IslandLayout(screen, position: position).top != layout.top else { return }
        configure(screen)
    }

    func configure(_ screen: NSScreen) {
        let next = IslandLayout(screen, position: position)
        let requested = IslandSurfaceConfiguration(notch: next.notch, top: next.top, scale: screen.backingScaleFactor)
        let update = requested.update(from: configuration, paletteVisible: panel?.isVisible == true,
                                      hasOverlays: !overlays.isEmpty, animating: !source.isIdle)
        // Until `closed` or the pill settles, the mask, panel and overlays keep the live layout.
        guard update != .deferred else { pending.hold(screen); return }
        pending.drop()
        self.screen = screen
        let moved = layout?.screen != next.screen || layout?.notch != next.notch || layout?.top != next.top
        layout = next
        canvas.scale = screen.backingScaleFactor
        canvas.show(glance: glance, level: level, notice: notice, statuses: statuses, expanded: expanded,
                    notch: next.notchWidth, song: song, songChange: songChange)
        backdrop.setFrame(next.window, display: false)
        if update == .recreate {
            surface = nil
            configuration = requested
        }
        if moved, let panel, panel.isVisible {
            let frame = next.contentFrame(panel.frame.size).offsetBy(dx: next.window.minX, dy: next.window.minY)
            panel.setFrameOrigin(frame.origin)
        }
        if surface != nil {
            frameChanged()
            return
        }
        var metrics = IslandMetrics.standard
        metrics.screen = .init(width: next.canvas.width, height: next.canvas.height)
        next.applyTops(to: &metrics)
        metrics.idle = .init(width: next.hasNotch ? next.notch.width : NotchTheme.Size.islandRest.width,
                             height: next.hasNotch ? next.notch.height * 2 : NotchTheme.Size.islandRest.height)
        metrics.corner.smoothing = 0
        metrics.expanded.sideInset = 0
        metrics.expanded.rowGap = 0
        metrics.expanded.centerTop = 0
        metrics.expanded.minHeight = NotchTheme.Size.islandRest.height
        metrics.expanded.maxHeight = next.canvas.height
        metrics.expanded.radius = Theme.Radius.panel
        metrics.expanded.shadow.pull = .init(side: 0, top: 0, bottom: 0, opacity: 0)
        metrics.sensor.opacity = 0
        metrics.compact.height = metrics.idle.height
        metrics.compact.sensorWidth = next.hasNotch ? next.notch.width : 0
        metrics.compact.edgePadding = Theme.Spacing.lg
        let inner = next.hasNotch ? Theme.Spacing.md : 0
        metrics.compact.innerPadding = .init(leading: inner, trailing: inner)
        // Each art caps its own wings; a song line that widens may reach the headline's width.
        metrics.compact.maxSlotWidth = NotchTheme.Size.islandHeadlineMaxWidth
        metrics.compact.maxWidth = next.canvas.width
        metrics.compact.balance = 0
        metrics.compact.radius = next.notchRadius.map(Double.init)
        let clock = FrameClock(frameSource: source)
        clock.timeScale = Self.motionSpeed
        let surface = IslandSurface<CGSize>(
            presentation: .idle, clock: clock, metrics: metrics,
            motion: .standard, dpr: screen.backingScaleFactor, reduced: reducedMotion,
            keyline: 0, stageWidth: Theme.Size.panelWidth, measure: { presentation, _ in
                switch presentation {
                case .expanded(let content):
                    ContentMeasures(expandedHeight: Double(content.bottom?.height ?? 0))
                case .compact(let content):
                    ContentMeasures(leading: Double(content.leading?.width ?? 0),
                                    trailing: Double(content.trailing?.width ?? 0))
                default: ContentMeasures()
                }
            })
        self.surface = surface
        surfaceMetrics = metrics
        source.display.host = canvas
        frameChanged()
    }

    @objc func frameChanged() {
        canvas.setAccessibilityValue(accessibilityValue)
        guard let surface, let layout else { return }
        surface.reduced = reducedMotion
        canvas.still = reducedMotion
        let sunk = panel.map { $0.isVisible && $0.level < Self.paletteLevel } ?? false
        let suspended = NSApp.modalWindow != nil || sunk
        if suspended { backdrop.orderOut(nil) }
        let palette = panel.flatMap { $0.isVisible ? $0.frame : nil }
        let overlay = IslandOverlayLayout(screen: layout.screen,
            contentTop: layout.openingTop, palette: palette,
            inset: NotchTheme.Spacing.islandInset, gap: Theme.Spacing.xl).surface(overlays)
        let size = CGSize(width: max(palette?.width ?? 0, overlay?.width ?? 0),
                          height: max(palette?.height ?? 0, overlay?.height ?? 0))
        glancing = size != .zero || page != nil || canvas.expansion != nil || level != nil || notice != nil
        let rests = showsRest && !onFullScreenSpace
        canvas.covered = size != .zero || page != nil
        surface.batch {
            if size != .zero {
                if !suspended { backdrop.orderFrontRegardless() }
                surface.expand(to: size, contentKey: "palette")
            } else if showsRest, let page = page?.frame.size {
                if !suspended { backdrop.orderFrontRegardless() }
                surface.expand(to: page, contentKey: "page")
            } else if showsRest || notice != nil, let line = canvas.headline {
                if !suspended { backdrop.orderFrontRegardless() }
                surface.expand(to: line.size, contentKey: "notice." + line.notice.id)
            } else if showsRest, let expansion = canvas.expansion, let art = canvas.glance {
                if !suspended { backdrop.orderFrontRegardless() }
                let width = max(expansion.size.width, glanceWidth(art.layout))
                surface.expand(to: CGSize(width: width, height: expansion.size.height), contentKey: "expansion")
            } else if showsRest || notice != nil, let art = canvas.glance {
                if rests || glancing, !suspended { backdrop.orderFrontRegardless() }
                let slots = CompactContent(leading: CGSize(width: art.layout.leading, height: 0),
                                           trailing: CGSize(width: art.layout.trailing, height: 0))
                surface.show(.compact(slots), contentKey: "glance")
            } else {
                if rests, !suspended { backdrop.orderFrontRegardless() }
                surface.show(.idle, contentKey: "rest")
            }
        }
        paintFrame()
    }

    func opened() {
        frameChanged()
    }

    /// Every island spring runs this many times faster, so an open or close lands in about 0.1 s (#884).
    static let motionSpeed = 4.0

    static let paletteLevel = NSWindow.Level(rawValue: IslandBackdrop.levelValue + 1)
    static let reportLevel = NSWindow.Level(rawValue: IslandBackdrop.levelValue + 2)
    static let questionLevel = NSWindow.Level(rawValue: IslandBackdrop.levelValue + 3)

    /// The engine's own switch; scenes force `.always` to prove Reduce Motion without system settings.
    var motion: ReducedMotionSetting = .user {
        didSet { frameChanged() }
    }

    private var reducedMotion: Bool {
        !Motion.isEnabled || motion.resolved(system: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private var isResting: Bool {
        guard let layout, let bounds = canvas.outline?.boundingBoxOfPath else { return false }
        let size = layout.hasNotch
            ? CGSize(width: layout.notch.width, height: layout.notch.height * 2) : NotchTheme.Size.islandRest
        let rest = canvas.headline.map { CGSize(width: $0.size.width, height: size.height + $0.size.height) }
            ?? CGSize(width: canvas.glance.map { glanceWidth($0.layout) } ?? size.width, height: size.height)
        return abs(bounds.width - rest.width) < 0.01 && abs(bounds.height - rest.height) < 0.01
    }

    private var surfaceMetrics: IslandMetrics?

    func glanceWidth(_ glance: IslandGlanceLayout) -> Double {
        guard let full = surfaceMetrics else { return 0 }
        let metrics = full.compact
        let sides = compactSides(SlotPair(leading: glance.leading, trailing: glance.trailing), metrics: full)
        let half = metrics.maxWidth / 2
        return min(metrics.sensorWidth / 2 + sides.leading, half) + min(metrics.sensorWidth / 2 + sides.trailing, half)
    }

    /// The pill's visible part, measured from the island window's top-left corner.
    var pillRect: CGRect? {
        guard let bounds = canvas.outline?.boundingBoxOfPath else { return nil }
        let height = canvas.bounds.height
        let top = max(height - bounds.maxY, 0)
        return CGRect(x: bounds.minX, y: top, width: bounds.width, height: height - bounds.minY - top)
    }

    /// Starts the close first, so a held configure sees it running and waits for it to settle.
    func closed() {
        frameChanged()
        applyPending()
    }

    private func applyPending() {
        if let screen = pending.release(blocked: panel?.isVisible == true || !overlays.isEmpty) { configure(screen) }
    }

    func setOverlays(_ frames: [CGRect]) {
        overlays = frames
        closed()
    }

    #if DEBUG
    /// Returns once the still is taken, so a scene can't change the pill before the frame lands.
    func capture(_ name: String) async {
        guard captureDone == nil else { IslandVerification.require(false, "one capture at a time"); return }
        captureName = name
        _ = source.requestFrame {}
        await withCheckedContinuation { captureDone = $0 }
    }

    private func takeCapture(panel: NSWindow?) {
        guard let captureName else { return }
        self.captureName = nil
        IslandVerification.capture(captureName, backdrop: backdrop, panel: panel)
        captured.append(captureName)
        captureDone?.resume()
        captureDone = nil
    }
    #endif

    private func paintFrame() {
        guard let layout, let surface else { return }
        let outline = surface.shape.paths.outline.cgPath
        var backgroundTransform = layout.stageTransform(width: surface.stageWidth)
        var contentTransform = panel.map {
            layout.maskTransform(width: surface.stageWidth, panel: $0.frame, flipped: $0.contentView?.isFlipped == true)
        } ?? backgroundTransform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.outline = outline.copy(using: &backgroundTransform)
        canvas.restWidth = layout.hasNotch ? layout.notch.width : NotchTheme.Size.islandRest.width
        canvas.restHeight = layout.hasNotch ? layout.notch.height * 2 : NotchTheme.Size.islandRest.height
        canvas.glanceWidth = canvas.glance.map { glanceWidth($0.layout) } ?? 0
        frost.paint(hasNotch: layout.hasNotch, settled: source.isIdle, reducedMotion: reducedMotion)
        canvas.display()
        clip.path = outline.copy(using: &contentTransform)
        keyline.path = clip.path
        if let page {
            var pageTransform = layout.maskTransform(width: surface.stageWidth, panel: page.frame,
                                                     flipped: page.contentView?.isFlipped == true)
            pageClip.path = outline.copy(using: &pageTransform)
        }
        keyline.lineWidth = 2 * canvas.keylineWidth
        keyline.strokeColor = canvas.keylineColor
        CATransaction.commit()
        CATransaction.flush()
        if !(showsRest && !onFullScreenSpace), !glancing, isResting { backdrop.orderOut(nil) }
        #if DEBUG
        recordFrame()
        if IslandVerification.enabled, let panel {
            let expected = canvas.outline?.boundingBoxOfPath.offsetBy(
                dx: backdrop.frame.minX, dy: backdrop.frame.minY) ?? .zero
            let local = clip.path?.boundingBoxOfPath ?? .zero
            let actual = CGRect(x: panel.frame.minX + local.minX,
                y: panel.contentView?.isFlipped == true ? panel.frame.maxY - local.maxY : panel.frame.minY + local.minY,
                width: local.width, height: local.height)
            let error = max(abs(expected.minX - actual.minX), abs(expected.minY - actual.minY),
                            abs(expected.maxX - actual.maxX), abs(expected.maxY - actual.maxY))
            samples.append("\(CACurrentMediaTime())\t\(panel.frame)\t\(backdrop.frame)\t\(expected)\t\(actual)\t\(error)")
            takeCapture(panel: panel)
        } else if IslandVerification.enabled {
            takeCapture(panel: nil)
        }
        #endif
    }

    isolated deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        canvas.animate(false)
        backdrop.orderOut(nil)
    }

    @MainActor
    private final class PanelObserver: NSObject {
        private let changed: () -> Void
        init(panel: NSWindow, changed: @escaping () -> Void) {
            self.changed = changed
            super.init()
            for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification,
                         NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(update), name: name, object: panel)
            }
        }
        @objc private func update() { changed() }
        isolated deinit { NotificationCenter.default.removeObserver(self) }
    }
}
