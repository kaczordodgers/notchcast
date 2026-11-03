import AppKit
import QuartzCore
import SwiftUI

final class IslandSurfaceView: NSView {
    private let silhouette = CAShapeLayer()
    private let openHost = HostingView(rootView: AnyView(EmptyView()))
    private let closedHost = HostingView(rootView: AnyView(EmptyView()))
    private var animationDisplayLink: CADisplayLink?
    private var showingOpen = false
    var onAnimationFrame: (() -> Void)?
    var onOpen: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.mask = silhouette
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Island"))
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

    func present(
        rect: CGRect, shoulder: CGFloat, radius: CGFloat, open: Bool, motion: IslandMotion
    ) {
        showingOpen = open
        let activeHost = open ? openHost : closedHost
        let inactiveHost = open ? closedHost : openHost
        activeHost.isHidden = false
        activeHost.setAccessibilityHidden(false)
        inactiveHost.setAccessibilityHidden(true)
        setAccessibilityRole(open ? .group : .button)
        let path = IslandSilhouette.path(in: rect, shoulder: shoulder, bottomRadius: radius)
        let previousPath = silhouette.presentation()?.path ?? silhouette.path ?? path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.frame = bounds
        silhouette.path = path
        if open { openHost.frame = rect } else { closedHost.frame = rect }
        CATransaction.commit()
        silhouette.removeAnimation(forKey: "islandMorph")
        if motion == .open || motion == .close {
            let animation = pathAnimation(motion)
            animation.fromValue = previousPath
            animation.toValue = path
            silhouette.add(animation, forKey: "islandMorph")
        }
        setOpacity(open ? 1 : 0, on: openHost, motion: motion)
        setOpacity(open ? 0 : 1, on: closedHost, motion: motion)
        if motion == .instant { inactiveHost.isHidden = true }
        onAnimationFrame?()
        if motion != .instant { watchAnimation() }
    }

    func containsIsland(_ point: CGPoint) -> Bool {
        let path = silhouette.presentation()?.path ?? silhouette.path
        return path?.contains(point) == true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard containsIsland(localPoint) else { return nil }
        let host = showingOpen ? openHost : closedHost
        return host.hitTest(localPoint) ?? self
    }

    override func accessibilityPerformPress() -> Bool {
        guard !showingOpen else { return false }
        onOpen?()
        return true
    }

    func stop() {
        animationDisplayLink?.invalidate()
        animationDisplayLink = nil
        silhouette.removeAllAnimations()
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

    private func setOpacity(_ opacity: Float, on host: NSView, motion: IslandMotion) {
        guard let layer = host.layer else { return }
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
        animation.duration = IslandMotion.fade.duration
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
        (showingOpen ? closedHost : openHost).isHidden = true
    }

    private final class HostingView: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
