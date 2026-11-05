// notchcast-sources: Tinycast/Features/GreenMaximize/Model/GreenMaximizeEngine.swift
// notchcast-sources: Tinycast/Features/GreenMaximize/Model/GreenMaximizeClick.swift
// notchcast-sources: Tinycast/Features/GreenMaximize/Service/GreenMaximizeRefresh.swift
import ApplicationServices
import CoreGraphics
import Foundation

@main
struct GreenMaximizeTest {
    static func main() {
        let original = CGRect(x: 200, y: 150, width: 700, height: 500)
        let visible = CGRect(x: -1920, y: 25, width: 1920, height: 1055)
        precondition(GreenMaximizeEngine.target(current: original, visible: visible, memory: nil) == visible)
        let memory = GreenMaximizeEngine.memory(original: original, requested: visible, applied: visible)
        precondition(memory != nil)
        precondition(GreenMaximizeEngine.target(current: visible, visible: visible, memory: memory) == original)
        let moved = visible.offsetBy(dx: 80, dy: 0)
        precondition(GreenMaximizeEngine.target(current: moved, visible: visible, memory: memory) == visible)
        precondition(GreenMaximizeEngine.memory(original: original, requested: visible, applied: original) == nil)
        precondition(GreenMaximizeEngine.memory(original: visible, requested: visible, applied: visible) == nil)
        precondition(GreenMaximizeEngine.target(current: .zero, visible: visible, memory: nil) == nil)
        precondition(GreenMaximizeEngine.target(current: original, visible: .zero, memory: nil) == nil)
        let invalid = CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100)
        precondition(GreenMaximizeEngine.target(current: invalid, visible: visible, memory: nil) == nil)
        let rect = CGRect(x: 20, y: 20, width: 14, height: 14)
        func hit(_ point: CGPoint = CGPoint(x: 25, y: 25), rect: CGRect? = rect,
                 age: Double = 0, option: Bool = false, exclusions: Set<String> = []) -> Bool {
            GreenMaximizeClick.intercept(point: point, rect: rect, age: age, option: option,
                bundleID: "test.app", exclusions: exclusions)
        }
        precondition(hit())
        precondition(!hit(CGPoint(x: 40, y: 25)))
        precondition(!hit(rect: nil))
        precondition(!hit(age: 2))
        precondition(!hit(age: -1))
        precondition(!hit(option: true))
        precondition(!hit(exclusions: ["test.app"]))
        testObserverTicks()
        testEvents()
        testPointerGate()
        let background = rect.offsetBy(dx: 100, dy: 0)
        func target(_ point: CGPoint, age: Double = 0, option: Bool = false,
                    exclusions: Set<String> = []) -> CGRect? {
            GreenMaximizeClick.target(pointer: background, frontmost: rect) { candidate in
                GreenMaximizeClick.intercept(point: point, rect: candidate, age: age,
                    option: option, bundleID: "test.app", exclusions: exclusions)
            }
        }
        precondition(target(CGPoint(x: 125, y: 25)) == background)
        precondition(target(CGPoint(x: 25, y: 25)) == rect)
        precondition(target(.zero) == nil)
        precondition(target(CGPoint(x: 125, y: 25), option: true) == nil)
        precondition(target(CGPoint(x: 125, y: 25), exclusions: ["test.app"]) == nil)
        precondition(target(CGPoint(x: 125, y: 25), age: 2) == nil)
        precondition(GreenMaximizeRefresh.buttonRect { _ in rect } == rect)
        precondition(GreenMaximizeRefresh.buttonRect { $0 == "AXFullScreenButton" ? rect : .zero } == rect)
        precondition(GreenMaximizeRefresh.buttonRect { $0 == "AXZoomButton" ? rect : .zero } == rect)
        precondition(GreenMaximizeRefresh.buttonRect { _ in .zero } == nil)
        print("green-maximize: geometry, button selection, observer and fake-event checks passed")
    }

    private static func testEvents() {
        var session = GreenMaximizeClick.Session()
        let hover = session.decide(.move, hit: true)
        precondition(hover.swallow && !hover.maximize)
        precondition(!session.decide(.move, hit: false).swallow)
        let down = session.decide(.down, hit: true)
        precondition(down.swallow && down.maximize)
        precondition(session.decide(.drag, hit: false).swallow)
        let up = session.decide(.up, hit: false)
        precondition(up.swallow && !up.maximize)
        precondition(!session.decide(.up, hit: true).swallow)
        precondition(!session.decide(.down, hit: false).swallow)
        precondition(!session.decide(.drag, hit: true).swallow)
        precondition(!session.decide(.up, hit: true).swallow)
    }

    private static func testPointerGate() {
        let bounds = CGRect(x: 100, y: 200, width: 800, height: 600)
        let zone = GreenMaximizeClick.PointerGate.zone(bounds: bounds, layer: 0)!
        precondition(zone == CGRect(x: 100, y: 200, width: 100, height: 40))
        precondition(GreenMaximizeClick.PointerGate.zone(bounds: bounds, layer: 1) == nil)
        var gate = GreenMaximizeClick.PointerGate(zones: [zone, zone.offsetBy(dx: 900, dy: 0)])
        precondition(!gate.moved(to: .zero))
        precondition(gate.moved(to: CGPoint(x: 110, y: 210)))
        precondition(!gate.moved(to: CGPoint(x: 120, y: 220)))
        precondition(gate.moved(to: CGPoint(x: 1010, y: 210)))
        precondition(gate.zone == 1)
        precondition(gate.moved(to: CGPoint(x: 110, y: 250)))
        precondition(gate.zone == nil)
        precondition(!gate.moved(to: CGPoint(x: 400, y: 400)))
        print("green-maximize: pointer zone gate and hop throttling passed")
    }

    private static func testObserverTicks() {
        var created = 0
        var observed: AXUIElement?
        for _ in 0..<3_600 {
            let focused = AXUIElementCreateApplication(getpid())
            _ = GreenMaximizeRefresh.newObserver(for: focused, observed: observed) { created += 1; return nil }
            observed = focused
        }
        precondition(created == 1, "An hour of ticks on one window registers one observer, got \(created)")
        _ = GreenMaximizeRefresh.newObserver(for: AXUIElementCreateApplication(1), observed: observed) {
            created += 1; return nil
        }
        precondition(created == 2, "A newly focused window registers its own observer")
        _ = GreenMaximizeRefresh.newObserver(for: AXUIElementCreateApplication(1), observed: nil) {
            created += 1; return nil
        }
        precondition(created == 3, "A failed or cleared observer is created again")
    }
}
