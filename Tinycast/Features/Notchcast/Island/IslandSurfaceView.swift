import AppKit
import QuartzCore
import SwiftUI

final class IslandSurfaceView: NSView {
    /// What the silhouette holds: the open pages, the closed row, or nothing while it is the launcher's black.
    enum Content { case open, closed, launcher }

    /// The silhouette's outline for one presentation.
    struct Outline: Equatable {
        var rect: CGRect
        var shoulder: CGFloat = 0
        var radius: CGFloat
        var topRadius: CGFloat = 0
        var bubble: CGFloat = 0
        var bubbleGap: CGFloat = 0

        var path: CGPath {
            IslandSilhouette.path(in: rect, shoulder: shoulder, bottomRadius: radius, topRadius: topRadius,
                                  bubble: bubble, bubbleGap: bubbleGap)
        }
    }

    private let silhouette = CAShapeLayer()
    private let fill = NSColor.black.cgColor
    /// The strip beside a camera that stays black while the rest fades under the launcher.
    private let band = NSView()
    private let openHost = HostingView(rootView: AnyView(EmptyView()))
    private let closedHost = HostingView(rootView: AnyView(EmptyView()))
    private var animationDisplayLink: CADisplayLink?
    private var showing = Content.closed
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
    }

    required init?(coder: NSCoder) { nil }

    func setOpenContent(_ view: AnyView) {
        openHost.rootView = view
    }

    func setClosedContent(_ view: AnyView) {
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
        presented = outline
        showing = content
        let activeHost = content == .open ? openHost : closedHost
        let inactiveHost = content == .open ? closedHost : openHost
        activeHost.isHidden = false
        activeHost.setAccessibilityHidden(content == .launcher)
        inactiveHost.setAccessibilityHidden(true)
        setAccessibilityRole(content == .closed ? .button : .group)
        let path = outline.path
        let previousPath = silhouette.presentation()?.path ?? silhouette.path ?? path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        silhouette.frame = bounds
        silhouette.path = path
        if content == .open { openHost.frame = outline.rect } else if content == .closed { closedHost.frame = outline.rect }
        CATransaction.commit()
        silhouette.removeAnimation(forKey: "islandMorph")
        if motion == .open || motion == .close {
            let animation = pathAnimation(motion)
            animation.fromValue = previousPath
            animation.toValue = path
            silhouette.add(animation, forKey: "islandMorph")
        }
        setOpacity(content == .open ? 1 : 0, on: openHost, motion: motion)
        setOpacity(content == .closed ? 1 : 0, on: closedHost, motion: motion)
        if motion == .instant { inactiveHost.isHidden = true }
        onAnimationFrame?()
        if motion != .instant { watchAnimation() }
    }

    /// The black itself, all but the band: out under the launcher, back in when it leaves.
    func setSurfaceOpacity(_ opacity: Float, duration: TimeInterval) {
        guard let layer, let color = fill.copy(alpha: CGFloat(opacity)) else { return }
        let previous = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.backgroundColor = color
        CATransaction.commit()
        layer.removeAnimation(forKey: "islandSurface")
        guard duration > 0, previous?.alpha != color.alpha else { return }
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = previous
        animation.toValue = color
        animation.duration = duration
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
        if showing != .open { openHost.isHidden = true }
        if showing != .closed { closedHost.isHidden = true }
    }

    private final class HostingView: NSHostingView<AnyView> {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
