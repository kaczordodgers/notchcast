import Foundation

struct NotchcastSettingsGroup: Identifiable {
    let title: LocalizedStringResource
    let items: [NotchcastSettingsItem]

    var id: String { title.key }
}

enum NotchcastSettingsItem: Hashable {
    case feature(NotchcastFeature, settings: [NotchcastSetting])
    case setting(NotchcastSetting)

    var feature: NotchcastFeature? {
        guard case .feature(let feature, _) = self else { return nil }
        return feature
    }

    var settings: [NotchcastSetting] {
        switch self {
        case .feature(_, let settings): settings
        case .setting(let setting): [setting]
        }
    }
}
