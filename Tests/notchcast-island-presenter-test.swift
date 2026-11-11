// notchcast-sources: Tinycast/Features/Notchcast/Activities/*.swift
// notchcast-kit: core
// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
import Foundation
import Observation
import Synchronization

enum DialogTone { case neutral, success, danger }
enum Theme {
    enum Duration { static let messageHUD: TimeInterval = 2.4 }
}

@main @MainActor struct IslandPresenterTests {
    static func changes(after write: () -> Void, on center: IslandActivityCenter) -> Int {
        let count = Mutex(0)
        withObservationTracking { _ = center.hasPresenter } onChange: { count.withLock { $0 += 1 } }
        write()
        return count.withLock { $0 }
    }

    static func main() {
        let center = IslandActivityCenter()
        precondition(changes(after: { center.hasPresenter = true }, on: center) == 1,
                     "Gaining a presenter notifies readers")
        precondition(changes(after: { center.hasPresenter = true }, on: center) == 0,
                     "A same-value presenter write on every pointer event must not notify readers")
        precondition(changes(after: { center.hasPresenter = false }, on: center) == 1,
                     "Losing the presenter notifies readers")
        precondition(changes(after: { center.hasPresenter = false }, on: center) == 0,
                     "Repeated loss must not notify readers")
        print("PASS: presenter availability notifies only on change")
    }
}
