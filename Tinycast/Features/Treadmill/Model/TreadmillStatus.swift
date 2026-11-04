import Foundation

struct TreadmillStatus: Equatable, Sendable {
    enum Phase: UInt8, Codable, Sendable {
        case standby = 0, ended = 1, countdown = 2, running = 3, slowing = 4
        case error = 5, asleep = 6, ready = 9, paused = 10
    }

    let phase: Phase
    let sample: TreadmillSample?
    let detail: UInt8

    init?(body: [UInt8]) {
        guard body.count == 2 || body.count == 15,
              let phase = Phase(rawValue: body[0]) else { return nil }
        let needsCounters = [.running, .slowing, .paused].contains(phase)
        guard !needsCounters || body.count == 15 else { return nil }
        self.phase = phase
        detail = body[1]
        if body.count == 15 {
            func word(_ index: Int) -> Int { Int(body[index]) | Int(body[index + 1]) << 8 }
            sample = TreadmillSample(speed: Double(body[1]) / 10, seconds: word(3),
                                     meters: word(5) * 10, kcal: Double(word(7)) / 10, steps: word(9))
        } else {
            sample = nil
        }
    }
}
