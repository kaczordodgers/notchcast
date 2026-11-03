import Foundation

nonisolated struct GPUReading: Sendable, Equatable {
    let id: UInt64
    let model: String
    let utilizationPercent: Double

    static func decode(id: UInt64, model: String, statistics: [String: Any]) -> Self? {
        let values = [statistics["Device Utilization %"], statistics["GPU Activity(%)"]]
        guard let percent = values.compactMap({ ($0 as? NSNumber)?.doubleValue })
            .first(where: { $0.isFinite && (0...100).contains($0) }) else { return nil }
        return Self(id: id, model: model, utilizationPercent: percent)
    }
}
