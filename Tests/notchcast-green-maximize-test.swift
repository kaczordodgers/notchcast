// notchcast-sources: Tinycast/Features/GreenMaximize/Model/GreenMaximizeEngine.swift
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
        print("green-maximize: 9 assertions passed")
    }
}
