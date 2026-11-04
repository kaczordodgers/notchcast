import Foundation

struct LinkHealthEngine: Sendable {
    enum Reachability: Sendable { case unknown, up, down }
    enum Notice: Sendable { case lost, recovered }

    private(set) var reachability: Reachability = .unknown
    private(set) var latency: Duration?
    private(set) var lastSeen: Date?
    private var successes = 0
    private var failures = 0

    mutating func consume(latency: Duration?, at date: Date) -> Notice? {
        if let latency, latency >= .zero {
            self.latency = latency
            lastSeen = date
            failures = 0
            successes = min(successes + 1, 2)
            guard reachability != .up, successes == 2 else { return nil }
            let recovering = reachability == .down
            reachability = .up
            return recovering ? .recovered : nil
        }
        self.latency = nil
        successes = 0
        failures = min(failures + 1, 2)
        guard reachability != .down, failures == 2 else { return nil }
        reachability = .down
        return .lost
    }
}
