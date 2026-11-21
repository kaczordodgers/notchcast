#if canImport(CoreGraphics)
import CoreGraphics
#else
import Foundation
#endif

enum TypingDisplay {
    struct Display: Sendable {
        let id: UInt32
        let bounds: CGRect
    }

    static func choose(displays: [Display], windows: [CGRect], pointer: UInt32?) -> UInt32? {
        guard let primary = displays.first else { return nil }
        guard displays.count > 1 else { return primary.id }
        let bounds = displays.map(\.bounds)
        for window in windows {
            if let index = index(showingMostOf: window, displayBounds: bounds) {
                return displays[index].id
            }
        }
        return displays.first { $0.id == pointer }?.id ?? primary.id
    }

    // Ported from Vorssaint (GPL-3.0-or-later); both frames use the window server's coordinates.
    static func index(showingMostOf window: CGRect, displayBounds: [CGRect]) -> Int? {
        guard !window.isNull, !window.isEmpty else { return nil }
        var best: (index: Int, area: CGFloat)?
        for (index, bounds) in displayBounds.enumerated() {
            let overlap = bounds.intersection(window)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            guard area > (best?.area ?? 0) else { continue }
            best = (index, area)
        }
        return best?.index
    }
}
