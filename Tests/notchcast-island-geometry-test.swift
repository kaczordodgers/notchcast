// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandGeometry.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandMotion.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandSilhouette.swift
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
        let pill = IslandGeometry.monitorPill(screen: screen, size: CGSize(width: 180, height: 28))
        let notch = CGRect(x: 660, y: 950, width: 192, height: 32)
        for hardware in [notch, nil] {
            let context = IslandClosedContext(screen: screen, hardwareNotch: hardware, pill: pill)
            expect(context.hasHardwareNotch == (hardware != nil), "context identifies the display shape")
            expect(context.screen == screen && context.pill == pill, "context preserves display geometry")
            expect(context.wingWidth(contentWidth: 12, minimum: 44) == (hardware == nil ? 12 : 44),
                   "only notch wings impose the 44 point floor")
            expect(context.wingWidth(contentWidth: 60, minimum: 44) == 60, "wide content keeps its width")
        }
    }

    static func screenSelection() {
        let screens = [CGRect(x: -1512, y: 0, width: 1512, height: 982),
                       CGRect(x: 0, y: -400, width: 1920, height: 1080)]
        for (point, expected) in [(CGPoint(x: -300, y: 970), 0), (CGPoint(x: 1500, y: 670), 1)] {
            let selected = IslandGeometry.screenIndex(containing: point, frames: screens)
            let open = screens.indices.map { $0 == selected }
            expect(selected == expected && open.filter { $0 }.count == 1,
                   "only the display under the pointer opens")
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
        expect(IslandMotion.choice(opening: true, reduceMotion: false, animationsEnabled: true) == .open,
               "opening uses the zero-bounce spring")
        expect(IslandMotion.choice(opening: false, reduceMotion: false, animationsEnabled: true) == .close,
               "closing uses ease-in-out")
        expect(IslandMotion.open.duration == 0.28 && IslandMotion.close.duration == 0.20,
               "the morph uses the specified open and close timings")
        for opening in [true, false] {
            expect(IslandMotion.choice(opening: opening, reduceMotion: true, animationsEnabled: true) == .fade,
                   "Reduce Motion removes geometry movement in either direction")
            for reduceMotion in [true, false] {
                expect(IslandMotion.choice(opening: opening, reduceMotion: reduceMotion,
                                           animationsEnabled: false) == .instant,
                       "the global animation switch takes precedence")
            }
        }
        expect(IslandMotion.fade.duration == 0.12, "Reduce Motion fades for 120 ms")
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
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
