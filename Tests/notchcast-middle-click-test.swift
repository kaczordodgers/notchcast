// notchcast-sources: Tinycast/Features/MiddleClick/Model/*.swift
// notchcast-sources: Tinycast/Features/MiddleClick/Service/MiddleClickTouchSource.swift
import CoreGraphics
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
        realFrames(fingers)
        rewrite()
        print("Middle click gesture, guards, button pairing, frame validation and event rewrite passed")
    }

    // Frame shapes MultitouchSupport delivers: staggered landings, lifting fingers kept in
    // the frame with a non-contact state, all three lifting in one frame, then an empty frame.
    static func realFrames(_ fingers: [TouchPoint]) {
        let lifted = fingers.map { TouchPoint(id: $0.id, x: $0.x, y: $0.y, down: false) }
        var gesture = ThreeFingerGesture()
        precondition(!gesture.frame(Array(fingers.prefix(1)), at: 10))
        precondition(!gesture.frame(Array(fingers.prefix(2)), at: 10.01))
        precondition(!gesture.frame(fingers, at: 10.02))
        precondition(gesture.frame(lifted, at: 10.12), "three fingers lifting in one frame are a tap")
        precondition(!gesture.frame(lifted, at: 10.13))
        precondition(!gesture.frame([], at: 10.14))

        precondition(!gesture.frame(fingers, at: 11))
        precondition(gesture.frame([], at: 11.1), "a frame emptied at once is a tap")

        precondition(!gesture.frame(fingers, at: 12))
        precondition(gesture.frame(Array(fingers.prefix(2)) + lifted.suffix(1), at: 12.1))
        precondition(!gesture.frame(Array(fingers.prefix(1)) + lifted.suffix(2), at: 12.11))
        precondition(!gesture.frame(lifted, at: 12.12), "one tap is one click")
        precondition(!gesture.frame([], at: 12.13))

        precondition(!gesture.frame(fingers, at: 13))
        precondition(!gesture.frame(fingers, at: 13.3))
        precondition(!gesture.frame(lifted, at: 13.31), "a rest longer than a tap is not a tap")
        precondition(!gesture.frame([], at: 13.32))

        let clock = Clock()
        let state = ThreeFingerState(clock: { clock.now })
        precondition(!state.frame(device: 1, touches: fingers, at: 0))
        clock.now += 0.1
        precondition(!state.frame(device: 1, touches: fingers, at: 0.1))
        precondition(state.press() == .middle, "a settled three-finger press is a middle click")
        clock.now += 0.05
        precondition(!state.frame(device: 1, touches: lifted, at: 0.15), "the press claims the touch")
        precondition(state.press() == .plain, "a click after the fingers lift is a plain click")
    }

    final class Clock: @unchecked Sendable {
        var now: TimeInterval = 100
    }

    static func rewrite() {
        for (decision, type) in [(MiddleClickFilter.Decision.down, CGEventType.otherMouseDown),
                                 (.drag, .otherMouseDragged), (.up, .otherMouseUp)] {
            let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                mouseCursorPosition: CGPoint(x: 40, y: 50), mouseButton: .left)!
            MiddleClickFilter.rewrite(event, for: decision)
            precondition(event.type == type)
            precondition(event.getIntegerValueField(.mouseEventButtonNumber) == 2)
            precondition(event.location == CGPoint(x: 40, y: 50))
        }
        let untouched = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                mouseCursorPosition: .zero, mouseButton: .left)!
        MiddleClickFilter.rewrite(untouched, for: .pass)
        precondition(untouched.type == .leftMouseDown)
    }
}
