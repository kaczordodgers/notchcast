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
        print("green-maximize: 19 assertions passed")
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
