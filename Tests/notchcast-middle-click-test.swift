// notchcast-sources: Tinycast/Features/MiddleClick/Model/*.swift
// notchcast-sources: Tinycast/Features/MiddleClick/Service/MiddleClickTouchSource.swift
import Foundation

@main
struct MiddleClickTests {
    static func main() {
        let fingers = (0..<3).map { TouchPoint(id: Int32($0), x: Float($0) / 10, y: 0.5, down: true) }
        var gesture = ThreeFingerGesture()
        precondition(!gesture.frame(fingers, at: 1))
        precondition(gesture.frame(Array(fingers.prefix(2)), at: 1.1))
        precondition(!gesture.frame([], at: 1.2))
        precondition(!gesture.frame(fingers, at: 2))
        precondition(!gesture.frame(Array(fingers.prefix(2)), at: 2.3))
        _ = gesture.frame([], at: 3)
        _ = gesture.frame(fingers, at: 3.1)
        var moved = fingers
        moved[0].x += 0.1
        precondition(!gesture.frame(moved, at: 3.15))
        precondition(!gesture.frame(Array(moved.prefix(2)), at: 3.2))
        _ = gesture.frame([], at: 4)
        _ = gesture.frame(fingers, at: 4.1)
        gesture.claimClick()
        precondition(!gesture.frame(Array(fingers.prefix(2)), at: 4.2))
        _ = gesture.frame([], at: 5)
        _ = gesture.frame(fingers + [TouchPoint(id: 8, x: 0.8, y: 0.5, down: true)], at: 5.1)
        precondition(!gesture.frame(fingers, at: 5.2))
        precondition(!gesture.frame([], at: 5.3))
        precondition(MiddleClickGuards.press(threeDown: true, frameAge: 1,
            settledFor: 1, sinceLastMiddle: nil) == .plain)
        precondition(MiddleClickGuards.press(threeDown: true, frameAge: 0,
            settledFor: 0.1, sinceLastMiddle: nil) == .middle)
        precondition(MiddleClickGuards.press(threeDown: false, frameAge: 0,
            settledFor: 0, sinceLastMiddle: 0.1) == .bounce)
        precondition(!MiddleClickGuards.tapAllowed(secondsSinceKeyDown: 0.1))
        var filter = MiddleClickFilter()
        precondition(filter.decide(.down, press: .middle) == .down)
        precondition(filter.decide(.drag, press: .plain) == .drag)
        precondition(filter.decide(.up, press: .plain) == .up)
        precondition(filter.decide(.up, press: .plain) == .pass)
        precondition(filter.decide(.down, press: .bounce) == .swallow)
        precondition(filter.decide(.up, press: .plain) == .swallow)
        _ = filter.decide(.down, press: .middle)
        precondition(filter.reset())
        precondition(filter.decide(.up, press: .plain) == .pass)
        precondition(MiddleClickTouchSource.isSane(fingers))
        moved[0].x = .nan
        precondition(!MiddleClickTouchSource.isSane(moved))
        print("Middle click gesture, guards, button pairing and frame validation passed")
    }
}
