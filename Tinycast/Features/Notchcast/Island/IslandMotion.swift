import CoreGraphics
import Foundation

/// What the silhouette holds: the open pages, the closed row, or nothing while it is the launcher's black.
enum IslandStage: Equatable { case open, closed, launcher }

/// How the silhouette moves from one presentation to the next; the curves live in `NotchcastTheme.Motion`.
enum IslandMotion: Equatable {
    /// Grows into the open pages or the launcher.
    case open
    /// Shrinks back to the closed row.
    case close
    /// A closed row changes shape: a status arrives, leaves, or a second one joins.
    case change
    /// Reduce Motion: the outline lands at once and only the content fades.
    case fade
    case instant

    static func choice(from: IslandStage, to: IslandStage, reduceMotion: Bool, animationsEnabled: Bool) -> Self {
        guard animationsEnabled else { return .instant }
        guard !reduceMotion else { return .fade }
        if to != .closed { return .open }
        return from == .closed ? .change : .close
    }

    /// The closed row fades back in once the island has landed; a changing row crossfades in place at once.
    var landsBeforeContent: Bool { self == .close }

    /// Core Animation morphs a path element by element, so a missing bubble is a circle of no size to grow from.
    static func morphPath(in rect: CGRect, shoulder: CGFloat, bottomRadius: CGFloat, topRadius: CGFloat,
                          bubble: CGFloat, bubbleGap: CGFloat) -> CGPath {
        guard bubble <= 0 else {
            return IslandSilhouette.path(in: rect, shoulder: shoulder, bottomRadius: bottomRadius,
                                         topRadius: topRadius, bubble: bubble, bubbleGap: bubbleGap)
        }
        let path = CGMutablePath()
        path.addPath(IslandSilhouette.path(in: rect, shoulder: shoulder, bottomRadius: bottomRadius,
                                           topRadius: topRadius))
        let bud = CGPoint(x: rect.maxX - rect.height / 2, y: rect.midY)
        path.addEllipse(in: CGRect(origin: bud, size: .zero))
        return path
    }

    /// How a new closed row takes over from the old one when what it shows changes; a value ticking in place cuts.
    enum Handover: Equatable {
        /// Both rows show a piece: the old row holds one beat, so that piece never dims.
        case holds
        /// Nothing is shared: the old row leaves at once, before the outline closes over it.
        case leaves
    }

    static func handover(from old: IslandClosedState, message oldMessage: UUID?,
                         to new: IslandClosedState, message newMessage: UUID?) -> Handover? {
        guard oldMessage != newMessage || old.look != new.look else { return nil }
        let shared = oldMessage == nil && newMessage == nil && !Set(old.look.pieces).isDisjoint(with: new.look.pieces)
        return shared ? .holds : .leaves
    }
}

private extension IslandClosedState {
    struct Look: Equatable {
        var primary: IslandActivity.Look?
        var secondary: IslandActivity.Look?
        /// The song, not whether it plays: the bars settle and start again in place.
        var music: [String]?

        var pieces: [AnyHashable] {
            [primary.map(AnyHashable.init), secondary.map(AnyHashable.init), music.map(AnyHashable.init)].compactMap { $0 }
        }
    }

    var look: Look {
        Look(primary: primary?.look, secondary: secondary?.look, music: music.map { [$0.title, $0.artist] })
    }
}

private extension IslandActivity {
    struct Look: Hashable {
        var id: UUID
        var title: String
        var symbol: String?
        var action: String?
        var value: Int?
    }

    var look: Look { Look(id: id, title: title, symbol: symbol, action: action, value: value.map(Self.slot)) }

    /// Which piece the value slot draws; its reading is left out.
    static func slot(_ value: Value) -> Int {
        switch value {
        case .timeLeft: 0
        case .elapsed: 1
        case .percent: 2
        case .count: 3
        case .step: 4
        case .number: 5
        case let .onOff(on): on ? 6 : 7
        case .spinner: 8
        }
    }
}
