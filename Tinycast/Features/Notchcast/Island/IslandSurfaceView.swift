import AppKit
import QuartzCore
import SwiftUI

final class IslandSurfaceView: NSView {
    private let silhouette = CAShapeLayer()
    private let openHost = HostingView(rootView: AnyView(EmptyView()))
    private let closedHost = HostingView(rootView: AnyView(EmptyView()))
    private var animationDisplayLink: CADisplayLink?
    var onAnimationFrame: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.mask = silhouette
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
        onAnimationFrame?()
        if motion != .instant { watchAnimation() }
    }

    func containsIsland(_ point: CGPoint) -> Bool {
        let path = silhouette.presentation()?.path ?? silhouette.path
        return path?.contains(point) == true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard containsIsland(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
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
        animation.duration = motion.duration
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
    }

    private final class HostingView: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
