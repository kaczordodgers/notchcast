// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandMotion.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandSilhouette.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/IslandClosedState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandActivity.swift
import CoreGraphics
import Foundation

@main
struct IslandMotionTests {
    static func main() {
        everyMorphInterpolates()
        missingBubbleGrowsFromTheBody()
        rowHandsOverOnlyWhenItsLookChanges()
        print("notchcast-island-motion: all checks passed")
    }

    /// Core Animation cuts a path morph whose element list differs, so every outline of one shape must match.
    static func everyMorphInterpolates() {
        let monitor = [
            path(CGRect(x: 0, y: 0, width: 180, height: 36), top: 18, radius: 18),
            path(CGRect(x: 0, y: 0, width: 262, height: 36), top: 18, radius: 18, bubble: 36),
            path(CGRect(x: 0, y: 0, width: 420, height: 36), top: 18, radius: 18),
            path(CGRect(x: 0, y: 0, width: 750, height: 475), top: 26, radius: 26),
            path(CGRect(x: 0, y: 0, width: 800, height: 120), top: 26, radius: 26),
        ]
        let notch = [
            path(CGRect(x: 0, y: 0, width: 196, height: 32), shoulder: 6, radius: 10),
            path(CGRect(x: 0, y: 0, width: 300, height: 32), shoulder: 6, radius: 10),
            path(CGRect(x: 0, y: 0, width: 300, height: 68), shoulder: 6, radius: 18),
            path(CGRect(x: 0, y: 0, width: 750, height: 507), shoulder: 10, top: 26, radius: 26),
        ]
        for family in [monitor, notch] {
            let first = elements(family[0])
            for outline in family.dropFirst() {
                expect(elements(outline) == first, "every outline of one shape has the same path elements")
            }
        }
    }

    static func missingBubbleGrowsFromTheBody() {
        let rect = CGRect(x: 0, y: 0, width: 180, height: 36)
        let bare = path(rect, top: 18, radius: 18)
        expect(bare.boundingBoxOfPath.equalTo(rect), "a missing bubble draws nothing outside the capsule")
        expect(bare.contains(CGPoint(x: 162, y: 18)), "a missing bubble sits inside the capsule's end")
        let budded = path(CGRect(x: 0, y: 0, width: 222, height: 36), top: 18, radius: 18, bubble: 36)
        expect(budded.contains(CGPoint(x: 204, y: 18)) && !budded.contains(CGPoint(x: 183, y: 18)),
               "a bubble stands apart from the body, a gap to its right")
    }

    static func rowHandsOverOnlyWhenItsLookChanges() {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 0)
        let downloading = IslandActivity(id: id, kind: .transfer, title: "Downloading", value: .percent(0.2))
        var ticked = downloading
        ticked.value = .percent(0.6)
        let timer = IslandActivity(id: id, kind: .timer, title: "Tea", value: .timeLeft(start))
        var later = timer
        later.value = .timeLeft(start.addingTimeInterval(-1))
        let song = IslandClosedState.Music(title: "Song", artist: "Artist", artwork: nil, isPlaying: true)
        var paused = song
        paused.isPlaying = false
        var next = song
        next.title = "Next"
        let none = IslandClosedState()
        let row = IslandClosedState(primary: downloading)
        func handover(_ old: IslandClosedState, _ new: IslandClosedState, _ oldMessage: UUID? = nil,
                      _ newMessage: UUID? = nil) -> IslandMotion.Handover? {
            IslandMotion.handover(from: old, message: oldMessage, to: new, message: newMessage)
        }
        expect(handover(row, IslandClosedState(primary: ticked)) == nil, "a percent ticking in place cuts")
        expect(handover(IslandClosedState(primary: timer), IslandClosedState(primary: later)) == nil,
               "a timer's date moving cuts")
        expect(handover(none, row) == .leaves && handover(row, none) == .leaves, "a status arriving or leaving")
        let pair = IslandClosedState(primary: downloading, secondary: timer)
        expect(handover(row, pair) == .holds && handover(pair, row) == .holds, "the shared status holds")
        var spinning = downloading
        spinning.value = .spinner
        expect(handover(row, IslandClosedState(primary: spinning)) == .leaves, "a value slot changing piece")
        var titled = downloading
        titled.title = "Done"
        expect(handover(row, IslandClosedState(primary: titled)) == .leaves, "a new word")
        expect(handover(IslandClosedState(music: song), IslandClosedState(music: paused)) == nil,
               "the bars settle in place")
        expect(handover(none, IslandClosedState(music: song)) == .leaves, "a song arriving")
        expect(handover(IslandClosedState(music: song), IslandClosedState(music: next)) == .leaves, "a new track")
        expect(handover(IslandClosedState(primary: timer), IslandClosedState(primary: timer, music: song)) == .holds,
               "a song joining a timer holds the timer")
        let message = UUID()
        expect(handover(row, row, nil, message) == .leaves && handover(row, row, message, nil) == .leaves,
               "a message in or out shares nothing with the row")
        expect(handover(none, none, message, message) == nil, "the same message cuts")
    }

    static func path(_ rect: CGRect, shoulder: CGFloat = 0, top: CGFloat = 0, radius: CGFloat,
                     bubble: CGFloat = 0) -> CGPath {
        IslandMotion.morphPath(in: rect, shoulder: shoulder, bottomRadius: radius, topRadius: top, bubble: bubble,
                               bubbleGap: 6)
    }

    static func elements(_ path: CGPath) -> [Int32] {
        var types: [Int32] = []
        path.applyWithBlock { types.append($0.pointee.type.rawValue) }
        return types
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
