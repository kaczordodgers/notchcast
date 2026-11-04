import Foundation

extension KatanaModule {
    static func confirmChannel(_ channel: KatanaChannel) async -> Bool {
        await AppCore.shared.confirm(
            title: String(localized: "Change the Katana channel?"), message: channel.title,
            symbol: "guitars", confirmTitle: String(localized: "Change Channel"),
            tone: .neutral, confirmRole: .standard)
    }
}
