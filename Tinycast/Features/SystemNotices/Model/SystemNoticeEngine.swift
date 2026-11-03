import Foundation

struct SystemNoticeEngine: Sendable {
    struct Battery: Sendable, Equatable {
        let percent: Int
        let onBattery: Bool
    }

    enum Reading: Sendable {
        case wifi(Bool?)
        case tailscale(TailscaleState)
        case battery(Battery?)
    }

    enum Notice: Sendable, Equatable {
        case wifi(available: Bool)
        case tailscale(TailscaleState)
        case lowBattery(percent: Int, threshold: Int)
    }

    private var wifi: Bool?
    private var tailscale: TailscaleState?
    private var battery: Battery?
    private var disarmedThresholds: Set<Int> = []

    mutating func consume(_ reading: Reading) -> [Notice] {
        switch reading {
        case .wifi(let next):
            defer { wifi = next }
            guard let next, let wifi, next != wifi else { return [] }
            return [.wifi(available: next)]
        case .tailscale(let next):
            defer { tailscale = next == .unavailable ? nil : next }
            guard next != .unavailable, let tailscale, next != tailscale else { return [] }
            return [.tailscale(next)]
        case .battery(let next):
            return consumeBattery(next)
        }
    }

    private mutating func consumeBattery(_ next: Battery?) -> [Notice] {
        guard let next, (0...100).contains(next.percent) else { battery = nil; return [] }
        let previous = battery
        battery = next
        for threshold in [20, 10] where next.percent >= threshold + 5 {
            disarmedThresholds.remove(threshold)
        }
        guard let previous else {
            if next.onBattery {
                for threshold in [20, 10] where next.percent <= threshold {
                    disarmedThresholds.insert(threshold)
                }
            }
            return []
        }
        guard next.onBattery else { return [] }
        let crossed = [20, 10].filter {
            next.percent <= $0 && !disarmedThresholds.contains($0)
                && (previous.percent > $0 || !previous.onBattery)
        }
        disarmedThresholds.formUnion(crossed)
        guard let threshold = crossed.min() else { return [] }
        return [.lowBattery(percent: next.percent, threshold: threshold)]
    }
}
