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

    func setContent(open: AnyView, closed: AnyView) {
        openHost.rootView = open
        closedHost.rootView = closed
    }

    /// Morphs to `outline` and shows one host. Every outline has the same path elements, so any two morph.
    func present(outline: IslandOutline, openRect: CGRect, showing: Showing, motion: IslandMotion) {
        self.showing = showing
        let hosts: [(HostingView, Showing)] = [(openHost, .open), (closedHost, .closed)]
        for (host, kind) in hosts where kind == showing {
            host.isHidden = false
            host.setAccessibilityHidden(false)
        }
        for (host, kind) in hosts where kind != showing { host.setAccessibilityHidden(true) }
        setAccessibilityRole(showing == .open ? .group : .button)
        let path = IslandSilhouette.path(outline)
        let previousPath = silhouette.presentation()?.path ?? silhouette.path ?? path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.frame = bounds
        silhouette.path = path
        openHost.frame = openRect
        closedHost.frame = bounds
        CATransaction.commit()
        silhouette.removeAnimation(forKey: "islandMorph")
        if motion == .open || motion == .close {
            let animation = pathAnimation(motion)
            animation.fromValue = previousPath
            animation.toValue = path
            silhouette.add(animation, forKey: "islandMorph")
        }
        for (host, kind) in hosts { setOpacity(kind == showing ? 1 : 0, on: host.layer, motion: motion) }
        if motion == .instant { for (host, kind) in hosts where kind != showing { host.isHidden = true } }
        onAnimationFrame?()
        if motion != .instant { watchAnimation() }
    }

    /// The whole island fading out onto the launcher, or back once the launcher has gone.
    func setVisible(_ visible: Bool, duration: TimeInterval) {
        setOpacity(visible ? 1 : 0, on: layer, motion: duration > 0 ? .fade : .instant, duration: duration)
    }

    var isMorphing: Bool { silhouette.animation(forKey: "islandMorph") != nil }

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
        animationDisplayLink?.invalidate()
        animationDisplayLink = nil
        silhouette.removeAllAnimations()
        layer?.removeAllAnimations()
        openHost.layer?.removeAllAnimations()
        closedHost.layer?.removeAllAnimations()
    }

    private func pathAnimation(_ motion: IslandMotion) -> CABasicAnimation {
        let animation: CABasicAnimation
        if motion == .open {
            animation = CASpringAnimation(perceptualDuration: motion.duration, bounce: 0)
        } else {
            animation = CABasicAnimation()
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        animation.keyPath = "path"
        animation.duration = (animation as? CASpringAnimation)?.settlingDuration ?? motion.duration
        return animation
    }

    private func setOpacity(_ opacity: Float, on layer: CALayer?, motion: IslandMotion,
                            duration: TimeInterval = IslandMotion.fade.duration) {
        guard let layer else { return }
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
        layer.add(animation, forKey: "islandContent")
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
              openHost.layer?.animation(forKey: "islandContent") == nil,
              closedHost.layer?.animation(forKey: "islandContent") == nil else { return }
        sender.invalidate()
        animationDisplayLink = nil
        if showing != .open { openHost.isHidden = true }
        if showing != .closed { closedHost.isHidden = true }
    }

    private final class HostingView: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
