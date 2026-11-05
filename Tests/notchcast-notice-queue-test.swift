// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandActivityCenter.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandActivity.swift
// notchcast-sources: Tinycast/Features/Notchcast/Activities/IslandMessage.swift
import Foundation

@MainActor
final class FakeNoticeClock {
    var durations: [TimeInterval] = []
    var sleepers: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: TimeInterval) async {
        durations.append(duration)
        await withCheckedContinuation { sleepers.append($0) }
    }

    func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    func advance() async {
        precondition(!sleepers.isEmpty)
        sleepers.removeFirst().resume()
        await settle()
    }
}

@main @MainActor
struct NoticeQueueTests {
    static func main() async {
        let clock = FakeNoticeClock()
        let center = IslandActivityCenter(sleep: { await clock.sleep($0) })
        var displayed: [String] = []
        func record(_ expected: String) {
            precondition(center.message?.text == expected)
            displayed.append(expected)
        }

        center.showMessage("Goal", tone: .success, dwell: 8)
        center.showMessage("Lube", tone: .neutral, dwell: 8)
        record("Goal")
        await clock.settle()
        precondition(clock.durations == [8])
        await clock.advance()
        record("Lube")
        precondition(clock.durations == [8, 8])
        await clock.advance()
        precondition(center.message == nil)

        center.showMessage("Keyboard battery", tone: .danger, dwell: 4)
        center.showMessage("Mouse battery", tone: .danger, dwell: 4)
        record("Keyboard battery")
        await clock.settle()
        await clock.advance()
        record("Mouse battery")
        await clock.advance()
        precondition(clock.durations == [8, 8, 4, 4])

        center.showMessage("Blocker", tone: .neutral, dwell: 1)
        center.showMessage("Old", tone: .neutral, dwell: 2, id: "device")
        center.showMessage("Tail", tone: .neutral, dwell: 3)
        center.showMessage("Latest", tone: .danger, dwell: 5, id: "device")
        await clock.settle()
        await clock.advance()
        record("Latest")
        precondition(center.message?.tone == .danger && clock.durations.last == 5)
        await clock.advance()
        record("Tail")
        await clock.advance()
        precondition(center.message == nil)

        center.showMessage("Active", tone: .neutral, dwell: 1)
        for index in 0..<10 {
            center.showMessage("Queued \(index)", tone: .neutral, dwell: 1)
        }
        record("Active")
        await clock.settle()
        for index in 2..<10 {
            await clock.advance()
            record("Queued \(index)")
        }
        await clock.advance()
        precondition(center.message == nil)

        center.showMessage("Canceled", tone: .neutral, dwell: 1)
        center.showMessage("Discarded", tone: .neutral, dwell: 1)
        await clock.settle()
        center.dismissMessage()
        center.showMessage("New", tone: .neutral, dwell: 2)
        await clock.settle()
        await clock.advance()
        record("New")
        await clock.advance()
        precondition(center.message == nil)
        center.showProgress("Working")
        center.showMessage("Finished", tone: .success, dwell: 2)
        record("Finished")
        await clock.settle()
        await clock.advance()
        precondition(center.message == nil)
        print("PASS: goal/lube and accessory FIFO, durations, coalescing, eight-slot cap, stale dismissal")
    }
}
