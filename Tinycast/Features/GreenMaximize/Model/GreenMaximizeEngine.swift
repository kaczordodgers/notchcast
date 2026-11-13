import CoreGraphics
import Foundation

struct GreenMaximizeEngine: Sendable {
    struct Memory: Equatable, Sendable {
        let original: CGRect
        let applied: CGRect
    }

    static func target(current: CGRect, visible: CGRect, memory: Memory?) -> CGRect? {
        guard valid(current), valid(visible) else { return nil }
        if let memory, matches(current, memory.applied), valid(memory.original) {
            return memory.original
        }
        return visible
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
