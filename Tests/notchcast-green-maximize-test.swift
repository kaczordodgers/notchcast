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
        precondition(!GreenMaximizeClick.intercept(point: CGPoint(x: 25, y: 25), rect: rect,
            age: 0, option: false, bundleID: "test.app", exclusions: [], verified: false))
        print("stale button covered by moved window: passed through")
        struct Window {
            let name: String
            let app: String
            let button: CGRect
        }
        let focused = Window(name: "focused window", app: "front.app", button: rect)
        let others = [
            Window(name: "inactive app", app: "other.app",
                button: CGRect(x: 220, y: 120, width: 14, height: 14)),
            Window(name: "non-focused window", app: "front.app",
                button: CGRect(x: 420, y: 220, width: 14, height: 14))
        ]
        let windowsByApp = ["front.app": [focused, others[1]], "other.app": [others[0]]]
        let candidates = ["front.app", "other.app"].flatMap { windowsByApp[$0] ?? [] }
        var failures = 0
        for window in others {
            let point = CGPoint(x: window.button.midX, y: window.button.midY)
            let resolved = GreenMaximizeClick.target(point: point, candidates: candidates, rect: { $0.button })
            let intercepted = GreenMaximizeClick.intercept(point: point, rect: resolved?.button,
                age: 0, option: false, bundleID: resolved?.app, exclusions: [])
            let maximized = intercepted && resolved?.name == window.name
                && GreenMaximizeEngine.target(current: original, visible: visible, memory: nil) == visible
            print("\(window.name): \(maximized ? "maximize" : "FAIL passed through")")
            if !maximized { failures += 1 }
        }
        guard failures == 0 else { exit(1) }
        let overlapping = Window(name: "top window", app: "other.app", button: rect)
        let zOrdered = [overlapping, focused]
        let top = GreenMaximizeClick.target(point: CGPoint(x: 25, y: 25),
            candidates: zOrdered, rect: { $0.button })
        precondition(top?.name == "top window")
        print("overlap in window z-order: top window selected")
        precondition(GreenMaximizeClick.target(point: CGPoint(x: 900, y: 900),
            candidates: candidates, rect: { $0.button }) == nil)
        print("green-maximize: geometry, click routing and passthrough passed")
    }
}
