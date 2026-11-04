import Foundation

extension TreadmillCoordinator {
    static func confirmStart() async -> Bool {
        await AppCore.shared.confirm(
            title: String(localized: "Start walking at 4 km/h?"), message: nil,
            symbol: "figure.walk", confirmTitle: String(localized: "Start Walk"),
            tone: .neutral, confirmRole: .standard)
    }
}
