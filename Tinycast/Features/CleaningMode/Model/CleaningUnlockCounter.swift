// Adapted from Vorssaint (GPL-3.0-or-later)
import Foundation

struct CleaningUnlockCounter: Sendable {
    private(set) var progress = 0
    private var lastPress: TimeInterval?

    mutating func registerKeyDown(code: Int64, time: TimeInterval, isRepeat: Bool) -> Bool {
        guard code == 53 else {
            reset()
            return false
        }
        guard !isRepeat else { return false }
        progress = lastPress.map { time >= $0 && time - $0 <= 6 ? progress + 1 : 1 } ?? 1
        lastPress = time
        return progress >= 5
    }

    mutating func reset() {
        progress = 0
        lastPress = nil
    }
}
