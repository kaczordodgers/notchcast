// notchcast-sources: Tinycast/Features/IslandHome/Model/*.swift Tinycast/Features/IslandHome/Service/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandActivity.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandActivityCenter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandMessage.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandValue.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandActivityPresenter.swift
import Foundation

@main
struct IslandHomeTests {
    @MainActor
    static func main() {
        let now = Date(timeIntervalSince1970: 1000)
        func entry(_ key: String, _ state: IslandHomeEntry.State = .result,
                   source: String = "downloads", age: Double = 0) -> IslandHomeEntry {
            IslandHomeEntry(id: .init(source: source, key: key), state: state,
                            title: key, date: now.addingTimeInterval(-age))
        }
        var model = IslandHomeModel(history: (0..<60).map { entry(String($0), age: Double($0)) })
        precondition(model.history.count == 50)
        precondition(model.entries(live: [], now: now).map(\.title) == ["0", "1", "2"])
        model.clear(model.history[0].id)
        model.clearAll()
        model.undoClear()
        model.undoClear()
        precondition(model.history.count == 50)
        model.clearAll()
        model.close()
        model.undoClear()
        precondition(model.history.isEmpty && !model.canUndo)

        let fakeFeeds = [entry("disk", .failure, source: "disk"),
                         entry("walk", .active, source: "walk"),
                         entry("backup", .attention, source: "time-machine"),
                         entry("track", .playing, source: "music"),
                         entry("speed", .message, source: "speedtest")]
        precondition(model.entries(live: fakeFeeds.reversed(), now: now).map(\.state)
                     == [.failure, .attention, .active, .playing, .message])
        var expired = entry("expired", .failure)
        expired.expires = now
        precondition(model.entries(live: [expired], now: now).isEmpty)
        let stale = entry("same", .active, age: 10)
        var fresh = entry("same", .failure)
        fresh.progress = .nan
        let deduped = model.entries(live: [fresh, stale], now: now)
        precondition(deduped.count == 1 && deduped[0].state == .failure && deduped[0].progress == nil)
        model.retain(entry("same"))
        precondition(model.entries(live: [fresh], now: now).count == 1)
        precondition(model.entries(live: (0..<40).map { entry(String($0), .active) }, now: now)
            .filter { $0.state == .active }.count == 20)
        var priority = entry("priority", .active)
        priority.priority = 100
        precondition(model.entries(live: [stale, priority], now: now).first?.title == "priority")
        let center = IslandActivityCenter(sleep: { _ in })
        let older = center.begin(IslandActivity(kind: .transfer, title: "Older", progress: 0.5))
        let urgent = center.begin(IslandActivity(kind: .timer, priority: 100, title: "Urgent", endDate: now))
        precondition(center.activities.first?.id == older)
        precondition(center.ranked.first?.id == urgent && center.current?.id == urgent)
        center.finish(older)
        center.finish(urgent)
        let id = center.begin(IslandActivity(kind: .timer, title: "Timer", endDate: now))
        let working = center.showProgress("Working")
        let adapted = IslandHomeActivityAdapter.entries(from: center, now: now)
        precondition(adapted.count == 2 && adapted.allSatisfy { $0.state == .active })
        center.finish(id)
        center.dismiss(working)
        precondition(IslandHomeActivityAdapter.entries(from: center, now: now).isEmpty)
        print("island-home: ranking, dedupe, expiry, limits, undo and activity adapter passed")
    }
}
