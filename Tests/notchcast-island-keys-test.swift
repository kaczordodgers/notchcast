// notchcast-sources: Tinycast/Features/Notchcast/Pages/IslandKey.swift
// notchcast-sources: Tinycast/Features/Notchcast/Pages/IslandPageFocus.swift
// notchcast-sources: Tinycast/Features/Notchcast/Pages/IslandPage.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/FavoriteSlots.swift
// notchcast-sources: Tinycast/Platform/ASCIIKeyboardLayout.swift
import Foundation

@main
struct IslandKeysTests {
    static func main() {
        keyMap()
        repeats()
        header()
        rows()
        print("notchcast-island-keys: key map, repeats, header focus and row selection passed")
    }

    static func key(_ code: UInt16, _ chord: IslandKey.Chord = .plain, repeat isRepeat: Bool = false,
                    _ character: String? = nil) -> IslandKey? {
        IslandKey.resolve(keyCode: code, chord: chord, isRepeat: isRepeat, character: character)
    }

    static func keyMap() {
        expect(key(35, .command, "p") == .pin && key(15, .command, "r") == .refresh, "⌘P pins, ⌘R refreshes")
        expect(key(35, .command, "P") == .pin, "the letter is compared case-blind")
        expect(key(18, .command, "&") == .page(.home) && key(19, .command, "é") == .page(.day),
               "⌘1 and ⌘2 follow the number row, so AZERTY's & and é still switch pages")
        expect(key(18, .command, "1") == .page(.home), "a plain digit layout switches pages too")
        expect(key(20, .command, "3") == nil && key(29, .command, "0") == nil, "unregistered page keys pass through")
        expect(key(53) == .close, "Escape closes")
        expect(key(36) == .activate && key(76) == .activate, "Return and keypad Enter activate")
        expect(key(123) == .header(-1) && key(124) == .header(1), "← and → move the header ring")
        expect(key(48) == .header(1) && key(48, .shift) == .header(-1), "Tab and ⇧Tab move the header ring")
        expect(key(125) == .selection(1) && key(126) == .selection(-1), "↓ and ↑ move the row")
        expect(key(0) == nil && key(35) == nil, "plain letters pass through")
        expect(key(35, .other, "p") == nil && key(53, .command) == nil, "other chords pass through")
        expect(key(36, .shift) == nil, "⇧Return is not the island's")
    }

    static func repeats() {
        expect(key(35, .command, repeat: true, "p") == .ignored, "a held ⌘P toggles the pin once")
        expect(key(15, .command, repeat: true, "r") == .ignored, "a held ⌘R refreshes once")
        expect(key(19, .command, repeat: true, "2") == .ignored, "a held ⌘2 cannot switch then close")
        expect(key(0, .command, repeat: true, "a") == nil, "a held foreign chord still passes through")
        expect(key(36, repeat: true) == .ignored, "a held Return activates once")
        expect(key(53, repeat: true) == .ignored, "a held Escape closes once")
        expect(key(125, repeat: true) == .selection(1) && key(124, repeat: true) == .header(1),
               "held arrows keep moving")
    }

    static func header() {
        let count = IslandPageFocus.headerCount
        expect(count == IslandPage.allCases.count + 2, "the header holds the pages, Pin and Settings")
        expect(IslandPageFocus.header(after: nil, shown: .day, delta: -1) == 0, "← from Day reaches Home")
        expect(IslandPageFocus.header(after: nil, shown: .day, delta: 1) == count - 2, "→ from Day reaches Pin")
        expect(IslandPageFocus.header(after: nil, shown: .home, delta: 1) == 1, "→ from Home reaches Day")
        expect(IslandPageFocus.header(after: nil, shown: .home, delta: -1) == count - 1, "← from Home wraps to Settings")
        expect(IslandPageFocus.header(after: count - 1, shown: .home, delta: 1) == 0, "→ past Settings wraps to Home")
        expect(IslandPageFocus.header(after: 1, shown: .home, delta: 1) == 2, "a ring already up moves from itself")
    }

    static func rows() {
        let ids = ["a", "b", "c"]
        expect(IslandPageFocus.selection(in: ids, stored: nil) == "a", "the first row starts selected")
        expect(IslandPageFocus.selection(in: ids, stored: "b") == "b", "a stored row stays selected")
        expect(IslandPageFocus.selection(in: ids, stored: "gone") == "a", "a vanished row falls back to the first")
        expect(IslandPageFocus.selection(in: [String](), stored: "a") == nil, "an empty list selects nothing")
        expect(IslandPageFocus.row(in: ids, from: nil, by: 1) == "b", "↓ from the default steps to the second row")
        expect(IslandPageFocus.row(in: ids, from: "c", by: 1) == "c", "↓ stops at the last row")
        expect(IslandPageFocus.row(in: ids, from: "a", by: -1) == "a", "↑ stops at the first row")
        expect(IslandPageFocus.row(in: ids, from: "gone", by: 1) == "b", "a vanished row moves from the first")
        expect(IslandPageFocus.row(in: [String](), from: nil, by: 1) == nil, "an empty list cannot move")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
