import AppKit
import QuartzCore
import SwiftUI

final class IslandSurfaceView: NSView {
    enum Showing: Equatable {
        case open
        case closed
        /// The black shape alone, growing into the launcher.
        case none
    }

    private let silhouette = CAShapeLayer()
    private let openHost = HostingView(rootView: AnyView(EmptyView()))
    private let closedHost = HostingView(rootView: AnyView(EmptyView()))
    private var outgoingHost: NSView?
    private var animationDisplayLink: CADisplayLink?
    private var showing = Showing.closed
    var onAnimationFrame: (() -> Void)?
    var onOpen: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NotchcastTheme.Colors.surfaceInk.cgColor
        layer?.mask = silhouette
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Island", table: "Notchcast"))
        for host in [openHost, closedHost] {
            host.sizingOptions = []
            host.wantsLayer = true
            addSubview(host)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        silhouette.contentsScale = layer?.contentsScale ?? 1
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        silhouette.contentsScale = window?.backingScaleFactor ?? layer?.contentsScale ?? 1
    }

    func setContent(open: AnyView, closed: AnyView, handover: Bool = false) {
        if handover, showing == .closed, let picture = snapshot(of: closedHost) {
            outgoingHost?.removeFromSuperview()
            let outgoing = NSView()
            outgoing.frame = closedHost.frame
            outgoing.wantsLayer = true
            outgoing.layer?.contents = picture
            outgoing.setAccessibilityHidden(true)
            addSubview(outgoing)
            outgoingHost = outgoing
            setOpacity(0, on: outgoing.layer, motion: .fade)
            setOpacity(0, on: closedHost.layer, motion: .instant)
        }
        openHost.rootView = open
        closedHost.rootView = closed
    }

    /// Morphs to `outline` and shows one host. Every outline has the same path elements, so any two morph.
    func present(outline: IslandOutline, openRect: CGRect, showing: Showing, motion: IslandMotion) {
        let path = IslandSilhouette.path(outline)
        guard motion != .fade else {
            let changes = silhouette.path != path || self.showing != showing
            present(outline: outline, openRect: openRect, showing: showing, motion: .instant)
            guard changes else { return }
            // Reduce Motion: the old island dissolves into the new one, shape and content together.
            layer?.add(Self.crossFade(), forKey: kCATransition)
            watchAnimation()
            return
        }
        let closing = showing == .closed && motion == .shrink
            && (self.showing == .open || outgoingHost != nil)
        self.showing = showing
        let hosts: [(HostingView, Showing)] = [(openHost, .open), (closedHost, .closed)]
        for (host, kind) in hosts where kind == showing {
            host.isHidden = false
            host.setAccessibilityHidden(false)
        }
        for (host, kind) in hosts where kind != showing { host.setAccessibilityHidden(true) }
        setAccessibilityRole(showing == .open ? .group : .button)
        let previousPath = silhouette.presentation()?.path ?? silhouette.path ?? path
        // The same outline again (an activity tick) keeps the spring already heading there.
        let retarget = motion == .instant || silhouette.path != path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.frame = bounds
        silhouette.path = path
        openHost.frame = openRect
        closedHost.frame = bounds
        CATransaction.commit()
        if retarget { silhouette.removeAnimation(forKey: "islandMorph") }
        if retarget, let spring = motion.spring {
            let animation = spring.animation
            animation.keyPath = "path"
            animation.duration = animation.settlingDuration
            animation.fromValue = previousPath
            animation.toValue = path
            if closing {
                animation.beginTime = silhouette.convertTime(CACurrentMediaTime(), from: nil) + IslandMotion.crossFade
                animation.fillMode = .backwards
            }
            silhouette.add(animation, forKey: "islandMorph")
        }
        for (host, kind) in hosts {
            let delay = kind == .closed && (closing || outgoingHost != nil)
                ? IslandMotion.crossFade + (closing ? IslandMotion.shrinking.time(reaching: 0.95) : 0) : 0
            setOpacity(kind == showing ? 1 : 0, on: host.layer, motion: motion, delay: delay)
        }
        if motion == .instant { for (host, kind) in hosts where kind != showing { host.isHidden = true } }
        onAnimationFrame?()
        if motion != .instant { watchAnimation() }
    }

    /// The delay runs on Core Animation's clock, so a busy main thread cannot hold the black over the launcher.
    func setVisible(_ visible: Bool, duration: TimeInterval, delay: TimeInterval = 0) {
        setAccessibilityShown(visible)
        setOpacity(visible ? 1 : 0, on: layer, motion: duration > 0 ? .fade : .instant, duration: duration,
                   delay: delay)
        if duration > 0 { watchAnimation() }
    }

    /// Hidden or serving as the launcher's surface, the island leaves the accessibility tree, not only the screen.
    func setAccessibilityShown(_ shown: Bool) {
        setAccessibilityElement(shown)
        openHost.setAccessibilityHidden(!shown || showing != .open)
        closedHost.setAccessibilityHidden(!shown || showing != .closed)
    }

    /// False once the island has dissolved entirely, so the next outline may snap unseen.
    var isShown: Bool { (layer?.presentation()?.opacity ?? layer?.opacity ?? 0) > 0 }

    func containsIsland(_ point: CGPoint) -> Bool {
        let path = silhouette.presentation()?.path ?? silhouette.path
        return path?.contains(point) == true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard showing != .none, containsIsland(localPoint) else { return nil }
        let host = showing == .open ? openHost : closedHost
        return host.hitTest(localPoint) ?? self
    }

    override func accessibilityPerformPress() -> Bool {
        guard showing == .closed else { return false }
        onOpen?()
        return true
    }

    func stop() {
        outgoingHost?.removeFromSuperview()
        outgoingHost = nil
        animationDisplayLink?.invalidate()
        animationDisplayLink = nil
        silhouette.removeAllAnimations()
        layer?.removeAllAnimations()
        openHost.layer?.removeAllAnimations()
        closedHost.layer?.removeAllAnimations()
    }

    private static func crossFade() -> CATransition {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = IslandMotion.crossFade
        return transition
    }

    private func setOpacity(_ opacity: Float, on layer: CALayer?, motion: IslandMotion,
                            duration: TimeInterval = IslandMotion.crossFade, delay: TimeInterval = 0) {
        guard let layer, motion == .instant || layer.opacity != opacity else { return }
        let previous = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
        layer.removeAnimation(forKey: "islandContent")
        guard motion != .instant, previous != opacity else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = previous
        animation.toValue = opacity
        animation.duration = duration
        if delay > 0 {
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
        }
        layer.add(animation, forKey: "islandContent")
    }

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
        guard silhouette.animation(forKey: "islandMorph") == nil,
              layer?.animation(forKey: "islandContent") == nil,
              layer?.animation(forKey: kCATransition) == nil,
              openHost.layer?.animation(forKey: "islandContent") == nil,
              closedHost.layer?.animation(forKey: "islandContent") == nil else { return }
        outgoingHost?.removeFromSuperview()
        outgoingHost = nil
        sender.invalidate()
        animationDisplayLink = nil
        if showing != .open { openHost.isHidden = true }
        if showing != .closed { closedHost.isHidden = true }
    }

    private final class HostingView: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
