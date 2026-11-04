import Foundation

struct ChargePolicy: Sendable, Equatable {
    struct Decision: Sendable, Equatable, Codable {
        var charging: Bool
        var adapter: Bool
        static let release = Self(charging: true, adapter: true)
    }

    var enabled = false
    var limit = 80
    var margin = 5
    var drain = true

    func decide(percent: Int?, charging: Bool, connected: Bool) -> Decision {
        guard enabled, connected, let percent, (0...100).contains(percent),
              Self.limits.contains(limit), (1...20).contains(margin) else { return .release }
        if limit == 100 { return .release }
        if drain && percent > limit { return Decision(charging: false, adapter: false) }
        let below = max(1, limit - margin)
        return Decision(charging: percent >= limit ? false : (percent < below ? true : charging),
                        adapter: true)
    }

    static let limits = Array(stride(from: 20, through: 100, by: 5))
}
