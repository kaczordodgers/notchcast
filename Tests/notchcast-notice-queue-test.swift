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

    /// Ends every dwell armed so far, including ones a re-arm already cancelled.
    func advance() async {
        precondition(!sleepers.isEmpty)
        let due = sleepers
        sleepers.removeAll()
        due.forEach { $0.resume() }
        await settle()
    }
}

@main @MainActor
struct NoticeQueueTests {
    static func main() async {
        let clock = FakeNoticeClock()
        let center = IslandActivityCenter(sleep: { await clock.sleep($0) })
        func expect(_ text: String?, _ label: String) {
            precondition(center.message?.text == text, "\(label): \(center.message?.text ?? "nil")")
        }

        center.showMessage("Goal", tone: .success, dwell: 8, id: "treadmill.goal")
        center.showMessage("Lube", tone: .neutral, dwell: 8, id: "treadmill.lube")
        await clock.settle()
        expect("Goal", "goal first")
        await clock.advance()
        expect("Lube", "lube after goal")
        await clock.advance()
        expect(nil, "queue drained")
        precondition(clock.durations == [8, 8])

        center.showMessage("Keyboard battery", tone: .danger, dwell: 4, id: "accessory.battery.1")
        center.showMessage("Mouse battery", tone: .danger, dwell: 4, id: "accessory.battery.2")
        await clock.settle()
        expect("Keyboard battery", "first accessory")
        await clock.advance()
        expect("Mouse battery", "second accessory")
        await clock.advance()
        expect(nil, "accessories drained")

        center.showMessage("Blocker", tone: .neutral, dwell: 1, id: "blocker")
        center.showMessage("Old", tone: .neutral, dwell: 2, id: "device")
        center.showMessage("Tail", tone: .neutral, dwell: 3, id: "tail")
        center.showMessage("Latest", tone: .danger, dwell: 5, id: "device")
        await clock.settle()
        await clock.advance()
        expect("Latest", "waiting id coalesced in its slot")
        precondition(center.message?.tone == .danger && clock.durations.last == 5)
        let visible = center.message?.id
        center.showMessage("Latest again", tone: .neutral, dwell: 6, id: "device")
        await clock.settle()
        expect("Latest again", "visible id updated in place")
        precondition(center.message?.id == visible && clock.durations.last == 6)
        await clock.advance()
        expect("Tail", "visible id never shown twice")
        await clock.advance()
        expect(nil, "coalescing drained")

        center.showMessage("Active", tone: .neutral, dwell: 1, id: "active")
        for index in 0..<10 {
            center.showMessage("Queued \(index)", tone: .neutral, dwell: 1, id: "queued.\(index)")
        }
        await clock.settle()
        expect("Active", "cap keeps visible")
        for index in 2..<10 {
            await clock.advance()
            expect("Queued \(index)", "eight newest kept")
        }
        await clock.advance()
        expect(nil, "cap drained")

        center.showMessage("Goal", tone: .success, dwell: 8, id: "treadmill.goal")
        center.showMessage("Lube", tone: .neutral, dwell: 8, id: "treadmill.lube")
        await clock.settle()
        center.showProgress("Rewriting…", onCancel: {})
        center.showMessage("Battery", tone: .danger, dwell: 4, id: "accessory.battery.1")
        precondition(center.message?.isProgress == true, "an id notice waits behind progress")
        center.dismissMessage()
        await clock.settle()
        expect("Lube", "hiding progress keeps the queue")
        await clock.advance()
        expect("Battery", "queue continues after dismissal")
        await clock.advance()
        expect(nil, "dismissal case drained")

        center.showMessage("Copied path", tone: .success, dwell: 2.4)
        await clock.settle()
        let copied = center.message?.id
        center.showMessage("Copied path", tone: .success, dwell: 2.4)
        await clock.settle()
        precondition(center.message?.id == copied, "repeat replaces in place")
        await clock.advance()
        expect(nil, "repeated text shows once")

        center.showMessage("Goal", tone: .success, dwell: 8, id: "treadmill.goal")
        center.showMessage("Lube", tone: .neutral, dwell: 8, id: "treadmill.lube")
        await clock.settle()
        center.showMessage("Copied text", tone: .success, dwell: 2.4)
        await clock.settle()
        expect("Copied text", "confirmation never waits")
        precondition(clock.durations.last == 2.4)
        await clock.advance()
        expect("Lube", "queue resumes after the confirmation")
        center.showProgress("Reading text…")
        center.showMessage("Copied text", tone: .success, dwell: 2.4)
        await clock.settle()
        expect("Copied text", "result replaces progress")
        await clock.advance()
        expect(nil, "confirmation case drained")
        print("PASS: id FIFO, coalescing, cap, dismissal keeps queue, id-less replace and resume")
    }
}
