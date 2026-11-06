// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandSurfaceView.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandSilhouette.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandMotion.swift
import AppKit
import QuartzCore
import SwiftUI

enum NotchcastTheme {
    enum Colors {
        static let surfaceInk = NSColor.black
    }
}

/// An activity tick re-presents the island with the outline it already has; that must neither restart the
/// silhouette's spring nor cut a content fade short.
@main
@MainActor
struct IslandSurfaceTests {
    static func main() {
        let surface = IslandSurfaceView(frame: CGRect(x: 0, y: 0, width: 800, height: 520))
        guard let mask = surface.layer?.mask, surface.subviews.count == 2,
              let openLayer = surface.subviews[0].layer else { fatalError("surface layers missing") }
        surface.layer?.contentsScale = 2
        surface.viewDidChangeBackingProperties()
        assert(mask.contentsScale == 2, "the silhouette must rasterize at the host's backing scale")
        let closed = IslandOutline(body: CGRect(x: 300, y: 488, width: 200, height: 32), bottomRadius: 10)
        let open = IslandOutline(body: CGRect(x: 0, y: 200, width: 800, height: 320), shoulder: 6, bottomRadius: 26)
        let openRect = open.body

        surface.present(outline: closed, openRect: openRect, showing: .closed, motion: .instant)
        assert(mask.animation(forKey: "islandMorph") == nil)
        surface.setContent(open: AnyView(EmptyView()), closed: AnyView(Text("Timer")))
        surface.setContent(open: AnyView(EmptyView()), closed: AnyView(Text("Done")), handover: true)
        surface.present(outline: closed, openRect: openRect, showing: .closed, motion: .shrink)
        assert(surface.subviews.count == 3 && surface.subviews[2].layer?.contents != nil,
               "handover retains a still image without restarting the outgoing row's geometry callbacks")
        let incoming = surface.subviews[1].layer?.animation(forKey: "islandContent") as? CABasicAnimation
        assert(incoming!.beginTime > CACurrentMediaTime() + IslandMotion.crossFade,
               "the replacement waits until the outgoing content has faded")
        surface.stop()

        surface.present(outline: open, openRect: openRect, showing: .open, motion: .open)
        guard let morph = mask.animation(forKey: "islandMorph"),
              let fade = openLayer.animation(forKey: "islandContent") else { fatalError("opening did not animate") }

        surface.present(outline: open, openRect: openRect, showing: .open, motion: .open)
        assert(mask.animation(forKey: "islandMorph") === morph, "the same outline restarted the spring")
        assert(openLayer.animation(forKey: "islandContent") === fade, "the same content cut its fade short")

        surface.present(outline: closed, openRect: openRect, showing: .closed, motion: .shrink)
        let closing = mask.animation(forKey: "islandMorph") as? CASpringAnimation
        assert(closing != nil && closing !== morph, "a new outline must retarget the morph")
        assert(closing!.beginTime > mask.convertTime(CACurrentMediaTime(), from: nil),
               "the open content must fade before the shape shrinks")
        assert(closing!.fillMode == .backwards, "the shape holds its old outline during content exit")
        assert(closing?.fromValue != nil && closing?.duration == closing?.settlingDuration,
               "a retarget starts where the shape is and runs until the spring settles")

        surface.present(outline: closed, openRect: openRect, showing: .closed, motion: .instant)
        assert(mask.animation(forKey: "islandMorph") == nil, "an instant present still snaps")

        surface.present(outline: open, openRect: openRect, showing: .open, motion: .fade)
        assert(mask.animation(forKey: "islandMorph") == nil, "Reduce Motion never moves the shape")
        assert(surface.layer?.animation(forKey: kCATransition) is CATransition, "Reduce Motion cross-fades the island")
        assert(surface.subviews[1].isHidden && openLayer.animation(forKey: "islandContent") == nil,
               "the cross-fade carries the content, so the hosts swap at once")
        surface.layer?.removeAnimation(forKey: kCATransition)
        surface.present(outline: open, openRect: openRect, showing: .open, motion: .fade)
        assert(surface.layer?.animation(forKey: kCATransition) == nil, "an unchanged island does not flash")

        surface.present(outline: closed, openRect: openRect, showing: .closed, motion: .instant)
        surface.setVisible(false, duration: 0)
        assert(!surface.isAccessibilityElement() && surface.subviews.allSatisfy { $0.isAccessibilityHidden() },
               "hidden under the launcher, VoiceOver must not reach the island")
        surface.setVisible(true, duration: 0)
        assert(surface.isAccessibilityElement() && !surface.subviews[1].isAccessibilityHidden()
               && surface.subviews[0].isAccessibilityHidden(), "back at rest, the closed island is reachable again")
        surface.present(outline: open, openRect: openRect, showing: .open, motion: .instant)

        surface.setVisible(false, duration: 0.12, delay: 0.2)
        guard let dissolve = surface.layer?.animation(forKey: "islandContent") as? CABasicAnimation,
              let layer = surface.layer else { fatalError("no dissolve") }
        assert(dissolve.beginTime > layer.convertTime(CACurrentMediaTime(), from: nil) + 0.15
               && dissolve.fillMode == .backwards && dissolve.fromValue as? Float == 1,
               "the dissolve waits on Core Animation's clock, holding the black until it starts")
        surface.setVisible(false, duration: 0.12)
        assert(surface.layer?.animation(forKey: "islandContent") === dissolve, "a repeated hide restarted the fade")
        surface.setVisible(true, duration: 0.18)
        assert(surface.layer?.opacity == 1 && surface.layer?.animation(forKey: "islandContent") !== dissolve)
        surface.setVisible(false, duration: 0)
        assert(!surface.isShown && surface.layer?.animation(forKey: "islandContent") == nil,
               "with animations off the island is gone at once")
        surface.stop()
        print("notchcast-island-surface: springs retarget, Reduce Motion cross-fades, the dissolve waits on CA")
    }
}
