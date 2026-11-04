import Foundation

struct TreadmillWalk: Codable, Equatable, Sendable {
    let started: Date
    var updated: Date
    var phase: TreadmillStatus.Phase
    var sample = TreadmillSample()
    var resumeSpeed: Double?

    var isValid: Bool {
        [started, updated].allSatisfy {
            $0.timeIntervalSince1970.isFinite && (0...253_402_300_799).contains($0.timeIntervalSince1970)
        }
            && updated >= started && sample.isValid
            && (resumeSpeed.map { $0.isFinite && TreadmillProtocol.speedRange.contains($0) } ?? true)
    }

    var record: TreadmillRecord {
        let hours = Double(sample.seconds) / 3600
        return TreadmillRecord(started: started.timeIntervalSince1970, ended: updated.timeIntervalSince1970,
                               seconds: Double(sample.seconds), meters: Double(sample.meters), kcal: sample.kcal,
                               steps: Double(sample.steps), averageKmh: hours > 0 ? Double(sample.meters) / 1000 / hours : 0)
    }
}
