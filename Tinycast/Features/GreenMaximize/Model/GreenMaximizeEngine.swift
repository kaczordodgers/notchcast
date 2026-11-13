import CoreGraphics
import Foundation

struct GreenMaximizeEngine: Sendable {
    struct Memory: Equatable, Sendable {
        let original: CGRect
        let applied: CGRect
    }

    static func target(current: CGRect, visible: CGRect, memory: Memory?, gap: CGFloat = 0) -> CGRect? {
        guard valid(current), valid(visible) else { return nil }
        if let memory, matches(current, memory.applied), valid(memory.original) {
            return memory.original
        }
        let inset = gap.isFinite && gap > 0 ? min(gap, min(visible.width, visible.height) / 10) : 0
        let canvas = visible.insetBy(dx: inset, dy: inset)
        return CGRect(x: canvas.minX.rounded(), y: canvas.minY.rounded(),
                      width: canvas.maxX.rounded() - canvas.minX.rounded(),
                      height: canvas.maxY.rounded() - canvas.minY.rounded())
    }

    static func memory(original: CGRect, requested: CGRect, applied: CGRect) -> Memory? {
        guard valid(original), valid(applied), matches(requested, applied),
              !matches(original, applied) else { return nil }
        return Memory(original: original, applied: applied)
    }

    private static func valid(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= 2 && abs(lhs.minY - rhs.minY) <= 2
            && abs(lhs.width - rhs.width) <= 2 && abs(lhs.height - rhs.height) <= 2
    }
}
