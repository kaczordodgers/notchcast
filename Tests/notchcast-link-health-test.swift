// notchcast-sources: Tinycast/Features/LinkHealth/Model/*.swift
// notchcast-sources: Tinycast/Features/LinkHealth/LinkHealthModule.swift
import Foundation

@MainActor
protocol NotchcastModule: AnyObject {
    func start()
    func stop()
}

@main
struct LinkHealthTests {
    @MainActor
    static func main() async {
        let date = Date(timeIntervalSince1970: 100)
        var engine = LinkHealthEngine()
        let transport: [Duration?] = [.milliseconds(12), .milliseconds(14), nil, .milliseconds(10), nil, nil,
                                      nil, .milliseconds(11), nil, .milliseconds(9), .milliseconds(8), .milliseconds(7)]
        var notices: [LinkHealthEngine.Notice] = []
        for (index, latency) in transport.enumerated() {
            if let notice = engine.consume(latency: latency, at: date.addingTimeInterval(Double(index))) {
                notices.append(notice)
            }
            if index == 1 { precondition(engine.reachability == .up) }
            if index == 5 {
                precondition(engine.reachability == .down)
                precondition(engine.latency == nil)
                precondition(engine.lastSeen == date.addingTimeInterval(3))
            }
        }
        precondition(notices.count == 2 && notices[0] == .lost && notices[1] == .recovered)
        precondition(engine.reachability == .up && engine.latency == .milliseconds(7))
        var down = LinkHealthEngine()
        precondition(down.consume(latency: nil, at: date) == nil)
        precondition(down.consume(latency: nil, at: date) == .lost)
        precondition(down.lastSeen == nil)

        var calls = 0
        let module = LinkHealthModule(probe: { calls += 1; return .milliseconds(1) }, now: { date }) { _ in
            preconditionFailure("No startup notice")
        }
        module.start()
        module.start()
        while calls == 0 { await Task.yield() }
        module.stop()
        await Task.yield()
        precondition(!module.isRunning && module.health.reachability == .unknown && calls == 1)
        var pending: CheckedContinuation<Duration, Never>?
        let delayed = LinkHealthModule(probe: {
            await withCheckedContinuation { pending = $0 }
        }, now: { date }) { _ in preconditionFailure("Stale notice") }
        delayed.start()
        while pending == nil { await Task.yield() }
        delayed.stop()
        pending?.resume(returning: .milliseconds(20))
        await Task.yield()
        precondition(delayed.health.lastSeen == nil)
        print("Link health: up, down, flapping, recovery once and lifecycle passed")
    }
}
