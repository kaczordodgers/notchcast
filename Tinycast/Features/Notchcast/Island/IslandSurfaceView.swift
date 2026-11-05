import AppKit
import QuartzCore
import SwiftUI

final class IslandSurfaceView: NSView {
    /// What the silhouette holds: the open pages, the closed row, or nothing while it is the launcher's black.
    typealias Content = IslandStage

    /// The silhouette's outline for one presentation.
    struct Outline: Equatable {
        var rect: CGRect
        var shoulder: CGFloat = 0
        var radius: CGFloat
        var topRadius: CGFloat = 0
        var bubble: CGFloat = 0
        var bubbleGap: CGFloat = 0

        var path: CGPath {
            IslandMotion.morphPath(in: rect, shoulder: shoulder, bottomRadius: radius, topRadius: topRadius,
                                   bubble: bubble, bubbleGap: bubbleGap)
        }

        /// Where the row centres: the body's middle, left of a bubble.
        var contentMidX: CGFloat {
            bubble > 0 ? rect.minX + (rect.width - bubble - bubbleGap) / 2 : rect.midX
        }
    }

    private let silhouette = CAShapeLayer()
    private let fill = NSColor.black.cgColor
    /// The strip beside a camera that stays black while the rest fades under the launcher.
    private let band = NSView()
    private let openHost = HostingView(rootView: AnyView(EmptyView()))
    private let closedHost = HostingView(rootView: AnyView(EmptyView()))
    /// The closed row a change replaced, fading out over its successor.
    private let outgoing = SnapshotView()
    private var animationDisplayLink: CADisplayLink?
    private(set) var showing = Content.closed
    private var presented: Outline?
    var onAnimationFrame: (() -> Void)?
    var onOpen: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = fill
        layer?.mask = silhouette
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Island", table: "Notchcast"))
        band.wantsLayer = true
        band.layer?.backgroundColor = fill
        band.isHidden = true
        band.setAccessibilityHidden(true)
        addSubview(band)
        for host in [openHost, closedHost] {
            host.sizingOptions = []
            host.wantsLayer = true
            addSubview(host)
        }
        openHost.isHidden = true
        openHost.layer?.opacity = 0
        outgoing.wantsLayer = true
        outgoing.isHidden = true
        outgoing.setAccessibilityHidden(true)
        addSubview(outgoing)
    }

    required init?(coder: NSCoder) { nil }

    func setOpenContent(_ view: AnyView) {
        openHost.rootView = view
    }

    /// A `crossfade` leaves a picture of the old row fading over the new one, so a change never pops.
    func setClosedContent(_ view: AnyView, handover: IslandMotion.Handover?) {
        if let handover, showing == .closed, !closedHost.isHidden, let layer = closedHost.layer,
           let picture = snapshot(of: closedHost) {
            let shown = layer.presentation()?.opacity ?? layer.opacity
            outgoing.image = picture
            outgoing.frame = closedHost.frame
            outgoing.isHidden = false
            if let fading = outgoing.layer {
                let holds = handover == .holds
                fade(fading, from: shown, to: 0, duration: NotchcastTheme.Motion.contentOut,
                     delay: holds ? NotchcastTheme.Motion.contentHold : 0, timing: holds ? .easeInEaseOut : .easeOut)
            }
            fade(layer, from: 0, to: 1, duration: NotchcastTheme.Motion.contentIn)
            watchAnimation()
        }
        closedHost.rootView = view
    }

    /// The camera band's height from the top edge; zero on a monitor, where nothing stays black.
    func setBand(height: CGFloat) {
        band.frame = CGRect(x: 0, y: bounds.height - height, width: bounds.width, height: height)
        band.isHidden = height <= 0
    }

    func present(_ outline: Outline, content: Content, motion: IslandMotion) {
        // A repeat of the settled target must not restart an in-flight morph from rest.
        guard motion == .instant || outline != presented || content != showing else { return }
        let previous = presented
        presented = outline
        showing = content
        let activeHost = content == .open ? openHost : closedHost
        let inactiveHost = content == .open ? closedHost : openHost
        activeHost.isHidden = false
        activeHost.setAccessibilityHidden(content == .launcher)
        inactiveHost.setAccessibilityHidden(true)
        setAccessibilityRole(content == .closed ? .button : .group)
        setAccessibilityElement(content != .launcher)
        let path = outline.path
        let previousPath = silhouette.presentation()?.path ?? silhouette.path ?? path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.frame = bounds
        silhouette.path = path
        if content == .open { openHost.frame = outline.rect } else if content == .closed { closedHost.frame = outline.rect }
        CATransaction.commit()
        silhouette.removeAnimation(forKey: "islandMorph")
        if let animation = springAnimation(motion, keyPath: "path") {
            animation.fromValue = previousPath
            animation.toValue = path
            silhouette.add(animation, forKey: "islandMorph")
        }
        if motion == .change, let previous { carry(by: previous.contentMidX - outline.contentMidX) }
        setOpacity(content == .open ? 1 : 0, on: openHost, motion: motion)
        setOpacity(content == .closed ? 1 : 0, on: closedHost, motion: motion)
        if content != .closed, !outgoing.isHidden, let layer = outgoing.layer {
            fade(layer, to: 0, duration: motion == .instant ? 0 : NotchcastTheme.Motion.contentOut)
        }
        if motion == .instant {
            inactiveHost.isHidden = true
            if content != .closed { outgoing.clear() }
        }
        onAnimationFrame?()
        if motion != .instant { watchAnimation() }
    }

    /// The black itself, all but the band: out under the launcher, back in when it leaves.
    func setSurfaceOpacity(_ opacity: Float, duration: TimeInterval, delay: TimeInterval = 0) {
        guard let layer, let color = fill.copy(alpha: CGFloat(opacity)) else { return }
        let previous = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        let target = layer.backgroundColor?.alpha
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color
        CATransaction.commit()
        guard duration <= 0 || target != color.alpha else { return }
        layer.removeAnimation(forKey: "islandSurface")
        guard duration > 0, previous?.alpha != color.alpha else { return }
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = previous
        animation.toValue = color
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        if delay > 0 {
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
        }
        layer.add(animation, forKey: "islandSurface")
    }

    func containsIsland(_ point: CGPoint) -> Bool {
        let path = silhouette.presentation()?.path ?? silhouette.path
        return path?.contains(point) == true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard containsIsland(localPoint) else { return nil }
        switch showing {
        case .open: return openHost.hitTest(localPoint) ?? self
        case .closed: return closedHost.hitTest(localPoint) ?? self
        case .launcher: return nil
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard showing == .closed else { return false }
        onOpen?()
        return true
    }

    func stop() {
        animationDisplayLink?.invalidate()
        animationDisplayLink = nil
        silhouette.removeAllAnimations()
        layer?.removeAllAnimations()
        openHost.layer?.removeAllAnimations()
        closedHost.layer?.removeAllAnimations()
        outgoing.clear()
    }

    /// The new row and the picture it replaced slide together on the morph's spring, so shared pieces never double.
    private func carry(by offset: CGFloat) {
        guard abs(offset) >= 1 else { return }
        if !outgoing.isHidden { outgoing.frame = outgoing.frame.offsetBy(dx: -offset, dy: 0) }
        for layer in [closedHost.layer, outgoing.isHidden ? nil : outgoing.layer].compactMap(\.self) {
            guard let animation = springAnimation(.change, keyPath: "transform.translation.x") else { return }
            animation.fromValue = offset
            animation.toValue = 0
            animation.isAdditive = true
            layer.add(animation, forKey: nil)
        }
    }

    /// Every silhouette change is a spring, so an interrupted morph picks up from wherever the shape is.
    private func springAnimation(_ motion: IslandMotion, keyPath: String) -> CASpringAnimation? {
        let spring: Spring
        switch motion {
        case .open, .change: spring = NotchcastTheme.Motion.grow
        case .close: spring = NotchcastTheme.Motion.shrink
        case .fade, .instant: return nil
        }
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.mass = CGFloat(spring.mass)
        animation.stiffness = CGFloat(spring.stiffness)
        animation.damping = CGFloat(spring.damping)
        animation.duration = animation.settlingDuration
        return animation
    }

    private func setOpacity(_ opacity: Float, on host: NSView, motion: IslandMotion) {
        guard let layer = host.layer else { return }
        guard motion != .instant else {
            fade(layer, to: opacity, duration: 0)
            return
        }
        // Already heading there: an in-flight fade keeps its course rather than restarting.
        guard layer.opacity != opacity else { return }
        let arriving = opacity > 0
        let waits = arriving && host === closedHost && motion.landsBeforeContent
        fade(layer, to: opacity, duration: arriving ? NotchcastTheme.Motion.contentIn : NotchcastTheme.Motion.contentOut,
             delay: waits ? NotchcastTheme.Motion.landing : 0)
    }

    private func fade(_ layer: CALayer, from start: Float? = nil, to opacity: Float, duration: TimeInterval,
                      delay: TimeInterval = 0, timing: CAMediaTimingFunctionName = .easeOut) {
        let from = start ?? layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
        layer.removeAnimation(forKey: "islandContent")
        guard duration > 0, from != opacity else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = opacity
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        if delay > 0 {
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
        }
        layer.add(animation, forKey: "islandContent")
    }

    /// The row as drawn, at the display's scale; the layer tree renders without its animations.
    private func snapshot(of view: NSView) -> CGImage? {
        guard let layer = view.layer, view.bounds.width > 0, view.bounds.height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let scale = window?.backingScaleFactor ?? 2
        guard let context = CGContext(
            data: nil, width: Int((view.bounds.width * scale).rounded(.up)),
            height: Int((view.bounds.height * scale).rounded(.up)), bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        if layer.isGeometryFlipped {
            context.translateBy(x: 0, y: view.bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        return context.makeImage()
    }

    private func watchAnimation() {
        guard animationDisplayLink == nil else { return }
        let link = displayLink(target: self, selector: #selector(animationFrame))
        animationDisplayLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func animationFrame(_ sender: CADisplayLink) {
        onAnimationFrame?()
        let layers = [silhouette, layer, openHost.layer, closedHost.layer, outgoing.layer]
        guard layers.allSatisfy({ $0?.animationKeys()?.isEmpty ?? true }) else { return }
        sender.invalidate()
        animationDisplayLink = nil
        if showing != .open { openHost.isHidden = true }
        if showing != .closed { closedHost.isHidden = true }
        outgoing.clear()
    }

    #if DEBUG
    /// For the motion stage: the closed row and the picture of the row it replaced.
    var stageViews: (closed: NSHostingView<AnyView>, outgoing: NSView) { (closedHost, outgoing) }
    #endif

    private final class HostingView: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    /// A still picture of a row; it never takes a click.
    private final class SnapshotView: NSView {
        var image: CGImage? {
            didSet { layer?.contents = image }
        }

        override var wantsUpdateLayer: Bool { true }
        override func updateLayer() { layer?.contents = image }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func clear() {
            isHidden = true
            image = nil
        }
    }
}
