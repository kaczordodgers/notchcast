// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandGeometry.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandMotion.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandSilhouette.swift
import CoreGraphics
import Foundation

@main
struct IslandGeometryTests {
    static func main() {
        notchGeometry()
        monitorGeometry()
        openGeometry()
        motionPolicy()
        silhouetteHitRegion()
        screenSelection()
        closedContext()
        print("notchcast-island-geometry: all checks passed")
    }

    static func closedContext() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let pill = IslandGeometry.monitorPill(screen: screen, size: CGSize(width: 120, height: 30), topGap: 4)
        expect(pill == CGRect(x: 696, y: 948, width: 120, height: 30), "the island floats 4 points under the top edge")
        let notch = CGRect(x: 660, y: 950, width: 192, height: 32)
        let launcher = CGRect(x: 381, y: 494, width: 750, height: 475)
        let closed = IslandOutline(body: notch, shoulder: 6, bottomRadius: 10)
        let open = IslandOutline(body: launcher, bottomRadius: 26, topRadius: 26)
        for outline in [closed, open, IslandOutline(body: pill, bottomRadius: 15, topRadius: 15,
                                                     bubble: CGRect(x: 826, y: 948, width: 30, height: 30))] {
            expect(elements(IslandSilhouette.path(outline)) == elements(IslandSilhouette.path(closed)),
                   "every outline has the same path elements, so any two morph")
        }
        let middle = IslandOutline.interpolate(closed, open, progress: 0.5)
        expect(middle.body.midX == notch.midX && middle.body.width == (notch.width + launcher.width) / 2
               && middle.shoulder == 3 && middle.topRadius == 13, "the middle frame is halfway in every parameter")
        expect(IslandOutline.interpolate(closed, open, progress: 1) == IslandOutline(
            body: launcher, bottomRadius: 26, topRadius: 26, bubble: open.parkedBubble), "the end frame is the launcher")
        expect(closed.parkedBubble.width == 0 && closed.body.contains(closed.parkedBubble.origin),
               "a missing bubble parks inside the body's trailing end")
        let capsule = IslandSilhouette.path(IslandOutline(body: pill, bottomRadius: 15, topRadius: 15))
        expect(!capsule.contains(CGPoint(x: pill.minX + 1, y: pill.maxY - 1)), "a detached pill rounds its top too")
        expect(capsule.contains(CGPoint(x: pill.midX, y: pill.midY)), "the pill's body takes clicks")
    }

    static func elements(_ path: CGPath) -> [Int32] {
        var types: [Int32] = []
        path.applyWithBlock { types.append($0.pointee.type.rawValue) }
        return types
    }

    static func screenSelection() {
        let screens = [CGRect(x: -1512, y: 0, width: 1512, height: 982),
                       CGRect(x: 0, y: -400, width: 1920, height: 1080)]
        for (point, expected) in [(CGPoint(x: -300, y: 970), 0), (CGPoint(x: 1500, y: 670), 1)] {
            let selected = IslandGeometry.screenIndex(containing: point, frames: screens)
            expect(selected == expected, "only the display under the pointer opens")
        }
        expect(IslandGeometry.screenIndex(containing: CGPoint(x: 4000, y: 0), frames: screens) == nil,
               "a removed or unknown display does not open another island")
        expect(IslandGeometry.screenIndex(containing: .zero, frames: []) == nil,
               "no displays means no open island")
    }

    static func notchGeometry() {
        let screen = CGRect(x: -1512, y: 100, width: 1512, height: 982)
        let left = CGRect(x: -1512, y: 1050, width: 656, height: 32)
        let right = CGRect(x: -656, y: 1050, width: 656, height: 32)
        let notch = IslandGeometry.notchRect(screen: screen, safeAreaTop: 32,
                                            leftArea: left, rightArea: right)
        expect(notch == CGRect(x: -856, y: 1050, width: 200, height: 32),
               "notch derives its global rectangle from the auxiliary strips")
        for inset: CGFloat in [0, -1, 1000] {
            expect(IslandGeometry.notchRect(screen: screen, safeAreaTop: inset,
                                            leftArea: left, rightArea: right) == nil,
                   "absent or invalid safe area does not invent a notch")
        }
        expect(IslandGeometry.notchRect(screen: screen, safeAreaTop: 32,
                                        leftArea: nil, rightArea: right) == nil,
               "missing auxiliary area uses the monitor presentation")
        expect(IslandGeometry.notchRect(screen: screen, safeAreaTop: 32,
                                        leftArea: right, rightArea: left) == nil,
               "overlapping auxiliary areas cannot describe a notch")
        let shifted = screen.offsetBy(dx: 4000, dy: -1500)
        let translated = IslandGeometry.notchRect(
            screen: shifted, safeAreaTop: 32,
            leftArea: left.offsetBy(dx: 4000, dy: -1500),
            rightArea: right.offsetBy(dx: 4000, dy: -1500))
        expect(translated == notch?.offsetBy(dx: 4000, dy: -1500),
               "rearranging screens preserves the notch's local geometry")
    }

    static func monitorGeometry() {
        let screen = CGRect(x: 1512, y: -400, width: 1920, height: 1080)
        let pill = IslandGeometry.monitorPill(screen: screen, size: CGSize(width: 180, height: 28))
        expect(pill == CGRect(x: 2382, y: 652, width: 180, height: 28),
               "monitor pill is centred and flush with the full screen's top edge")
        expect(IslandGeometry.monitorPill(screen: screen, size: CGSize(width: 9000, height: 9000)) == screen,
               "pill is clamped to a small display")
    }

    static func openGeometry() {
        let screen = CGRect(x: -1512, y: -100, width: 1512, height: 982)
        let open = IslandGeometry.openFrame(
            screen: screen, centerX: screen.midX, minimumWidth: 800,
            contentHeight: 96, headerHeight: 32, maximumHeight: 475)
        expect(open.width == 800 && open.height == 128 && open.maxY == screen.maxY,
               "built-in open frame reserves the header and fits its content")
        expect(open.midX == screen.midX, "open frame remains centred on the camera")
        let tall = IslandGeometry.openFrame(
            screen: screen, centerX: screen.midX, minimumWidth: 800,
            contentHeight: 2000, headerHeight: 36, maximumHeight: 475)
        expect(tall.height == 475 && tall.maxY == screen.maxY, "tall content respects the height cap")
        let empty = IslandGeometry.openFrame(
            screen: screen, centerX: screen.midX, minimumWidth: 800,
            contentHeight: -200, headerHeight: 36, maximumHeight: 475)
        expect(empty.height == 36, "empty content retains the monitor header")
        let smallScreen = CGRect(x: 100, y: 400, width: 600, height: 300)
        let small = IslandGeometry.openFrame(
            screen: smallScreen, centerX: smallScreen.midX, minimumWidth: 800,
            contentHeight: 600, headerHeight: 32, maximumHeight: 475)
        expect(small == smallScreen, "width and height clamp to the actual screen")
        for center: CGFloat in [-9000, 9000] {
            let clamped = IslandGeometry.openFrame(
                screen: screen, centerX: center, minimumWidth: 800,
                contentHeight: 96, headerHeight: 32, maximumHeight: 475)
            expect(screen.contains(clamped), "an off-centre camera cannot push content offscreen")
        }
    }

    static func motionPolicy() {
        let notch = IslandOutline(body: CGRect(x: 660, y: 950, width: 192, height: 32), bottomRadius: 10)
        let music = IslandOutline(body: CGRect(x: 600, y: 950, width: 312, height: 32), shoulder: 6, bottomRadius: 10)
        let open = IslandOutline(body: CGRect(x: 381, y: 600, width: 750, height: 382), shoulder: 14, bottomRadius: 26)
        func choice(_ from: IslandOutline?, _ to: IslandOutline, opening: Bool = false, reduceMotion: Bool = false,
                    animationsEnabled: Bool = true) -> IslandMotion {
            IslandMotion.choice(from: from, to: to, opening: opening, reduceMotion: reduceMotion,
                                animationsEnabled: animationsEnabled)
        }
        expect(choice(notch, open, opening: true) == .open, "opening grows")
        expect(choice(notch, music) == .grow, "a closed state widening grows")
        expect(IslandMotion.open.spring == IslandMotion.grow.spring, "opening and widening share the one grow spring")
        expect(choice(music, notch) == .shrink && choice(open, notch) == .shrink, "back to rest never swings")
        expect(choice(nil, notch) == .shrink, "the first outline has nothing to grow from")
        let bubble = IslandOutline(body: music.body, bottomRadius: 15, topRadius: 15,
                                   bubble: CGRect(x: 922, y: 950, width: 32, height: 32))
        expect(choice(IslandOutline(body: music.body, bottomRadius: 15, topRadius: 15), bubble) == .grow,
               "a bubble beading out grows")
        for opening in [true, false] {
            expect(choice(notch, music, opening: opening, reduceMotion: true) == .fade,
                   "Reduce Motion removes geometry movement in either direction")
            for reduceMotion in [true, false] {
                expect(choice(notch, music, opening: opening, reduceMotion: reduceMotion,
                              animationsEnabled: false) == .instant, "the global animation switch takes precedence")
            }
        }
        expect(IslandMotion.fade.spring == nil && IslandMotion.instant.spring == nil, "nothing moves without motion")
        expect(IslandMotion.crossFade == 0.12, "Reduce Motion cross-fades for 120 ms")
        springTiming()
    }

    /// The springs the silhouette runs, solved the way Core Animation runs them.
    static func springTiming() {
        let open = IslandMotion.growing.curve()
        let shrink = IslandMotion.shrinking.curve()
        let samples = stride(from: 0.0, through: 1.5, by: 0.005)
        expect(zip(samples, samples.dropFirst()).allSatisfy { open($0) <= open($1) && shrink($0) <= shrink($1) },
               "the growing and shrinking springs never turn back")
        expect(samples.allSatisfy { open($0) <= 1 && shrink($0) <= 1 },
               "no island spring overshoots: the row would leave the notch's edge")
        expect(abs(shrink(1.5) - 1) < 0.001 && abs(open(1.5) - 1) < 0.001, "every spring settles")
        let handoff = IslandMotion.growing.time(reaching: 0.95)
        expect(handoff > 0.18 && handoff < IslandMotion.growing.duration,
               "the dissolve hands off before the perceptual duration (\(handoff))")
        expect(open(handoff) >= 0.95 && open(handoff - 0.001) < 0.95, "the handoff is the first moment at 95%")
        expect(IslandMotion.growing.time(reaching: 2) <= Double(IslandMotion.growing.animation.settlingDuration),
               "an unreachable progress stops at the settling time")
        expect(IslandMotion.shrinking.duration < IslandMotion.growing.duration,
               "back to rest is quicker than the opening")
    }

    static func silhouetteHitRegion() {
        let rect = CGRect(x: 0, y: 0, width: 180, height: 28)
        let pill = IslandSilhouette.path(in: rect, shoulder: 0, bottomRadius: 10)
        expect(pill.contains(CGPoint(x: 90, y: 14)), "monitor pill has no centre gap")
        expect(!pill.contains(CGPoint(x: 1, y: 1)), "transparent lower corners pass clicks through")
        let notch = IslandSilhouette.path(in: rect, shoulder: 6, bottomRadius: 10)
        expect(!notch.contains(CGPoint(x: 1, y: 20)), "transparent concave shoulders pass clicks through")
        expect(notch.contains(CGPoint(x: 90, y: 14)), "the notch body accepts mouse events")
        expect(!notch.contains(CGPoint(x: 90, y: -1)), "the canvas below the silhouette passes clicks through")
        silhouetteCorners()
    }

    static func silhouetteCorners() {
        let notch = IslandSilhouette.shoulder(height: 32, cap: 14)
        let radius = IslandSilhouette.bottomRadius(height: 32, cap: 26)
        expect(abs(notch - 6.08) < 0.01 && abs(radius - 10.88) < 0.01,
               "a notch-tall strip keeps the cutout's small corners")
        expect(IslandSilhouette.shoulder(height: 475, cap: 14) == 14
               && IslandSilhouette.bottomRadius(height: 475, cap: 26) == 26, "a tall island stops at the caps")
        expect(IslandSilhouette.shoulder(height: -4, cap: 14) == 0
               && IslandSilhouette.bottomRadius(height: 32, cap: -1) == 0, "negative input never inverts a corner")
        expect(IslandMotion.shrinking.bounce == 0 && IslandMotion.growing.bounce == 0, "no island spring bounces")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
