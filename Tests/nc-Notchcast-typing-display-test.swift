// notchcast-linux-ok
// notchcast-sources: Tinycast/Features/Notchcast/Core/Model/TypingDisplay.swift
#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

@main
enum TypingDisplayTest {
    static func main() {
        let primary = TypingDisplay.Display(id: 1, bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let other = TypingDisplay.Display(id: 2, bounds: CGRect(x: 1000, y: 0, width: 1000, height: 800))
        let first = CGRect(x: 40, y: 50, width: 300, height: 200)
        let second = CGRect(x: 1100, y: 50, width: 300, height: 200)
        let displays = [primary, other]

        precondition(TypingDisplay.choose(displays: [], windows: [second], pointer: 2) == nil)
        precondition(TypingDisplay.choose(displays: [primary], windows: [second], pointer: 2) == 1)
        precondition(TypingDisplay.choose(displays: displays, windows: [second], pointer: 1) == 2)
        let straddling = CGRect(x: 900, y: 50, width: 300, height: 200)
        let tied = CGRect(x: 900, y: 50, width: 200, height: 200)
        precondition(TypingDisplay.choose(displays: displays, windows: [straddling], pointer: 1) == 2)
        precondition(TypingDisplay.choose(displays: displays, windows: [tied], pointer: 2) == 1)
        precondition(TypingDisplay.choose(displays: displays, windows: [second, first], pointer: 1) == 2)

        let off = CGRect(x: 2000, y: 0, width: 100, height: 100)
        let unusable: [CGRect] = [.zero, .null, off]
        precondition(TypingDisplay.choose(displays: displays, windows: unusable + [second], pointer: 1) == 2)
        precondition(TypingDisplay.choose(displays: displays, windows: unusable, pointer: 2) == 2)
        precondition(TypingDisplay.choose(displays: displays, windows: [], pointer: 17) == 1)
        precondition(TypingDisplay.choose(displays: displays, windows: unusable, pointer: nil) == 1)

        for origin in [CGPoint(x: -1000, y: 0), CGPoint(x: 0, y: -800)] {
            let beside = TypingDisplay.Display(id: 3, bounds: CGRect(origin: origin, size: primary.bounds.size))
            let window = first.offsetBy(dx: origin.x, dy: origin.y)
            precondition(TypingDisplay.choose(displays: [primary, beside], windows: [window], pointer: nil) == 3)
        }
        print("PASS typing display: window order, overlap, ties, negative origins and fallbacks")
    }
}
