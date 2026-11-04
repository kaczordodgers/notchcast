// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettings*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSetting.swift
import Foundation

@main
struct NotchcastSettingsTreeTests {
    static func main() throws {
        let modules = NotchcastSettingsModule.allCases
        precondition(modules.count == 18, "Expected 18 modules")
        var featureCounts: [NotchcastFeature: Int] = [:]
        var settingCounts: [NotchcastSetting: Int] = [:]
        for module in modules {
            precondition(!module.groups.isEmpty, "Empty module: \(module)")
            precondition(Set(module.groups.map(\.id)).count == module.groups.count, "Repeated group ID: \(module)")
            precondition(NotchcastSettingsModule(tab: module.tab) == module, "Tab mapping: \(module)")
            precondition(SettingsTab(slug: module.slug) == module.tab, "Slug mapping: \(module)")
            for group in module.groups {
                precondition(!group.items.isEmpty, "Empty group: \(module)/\(group.id)")
                for item in group.items {
                    if let feature = item.feature {
                        featureCounts[feature, default: 0] += 1
                        precondition(NotchcastSettingsModule.module(of: feature) == module, "Feature owner: \(feature)")
                    }
                    for setting in item.settings {
                        settingCounts[setting, default: 0] += 1
                        precondition(NotchcastSettingsModule.module(of: setting) == module, "Setting owner: \(setting)")
                    }
                }
            }
        }
        for feature in NotchcastFeature.allCases {
            precondition(featureCounts[feature] == 1, "Feature \(feature) placed \(featureCounts[feature, default: 0]) times")
        }
        for setting in NotchcastSetting.allCases {
            precondition(settingCounts[setting] == 1, "Setting \(setting) placed \(settingCounts[setting, default: 0]) times")
        }
        precondition(NotchcastSettingsModule.island.tab == .notchcast, "Legacy Island tab")
        precondition(NotchcastSettingsModule.island.slug == "notchcast", "Legacy Island slug")
        precondition(NotchcastSettingsModule(tab: .general) == nil, "Upstream tab rejected")
        precondition(SettingsSection.notchcast.tabs == modules.map(\.tab), "Sidebar order")
        precondition(!SettingsSection.features.tabs.contains(.notchcast), "Island moved out of Features")
        let data = try Data(contentsOf: URL(filePath: "Tinycast/Resources/Localizable.xcstrings"))
        let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let strings = catalog?["strings"] as? [String: [String: Any]] else {
            fatalError("Missing string catalog")
        }
        let titles = modules.map(\.title) + modules.flatMap(\.groups).map { $0.title.key }
        for title in Set(titles) {
            guard let translations = strings[title]?["localizations"] as? [String: [String: Any]] else {
                fatalError("Missing title: \(title)")
            }
            for language in ["de", "es", "fr", "ja", "ko", "pt", "ru", "zh-Hans"] {
                let unit = translations[language]?["stringUnit"] as? [String: String]
                precondition(unit?["state"] == "translated", "Missing \(language) translation: \(title)")
            }
        }
        print("PASS: \(modules.count) modules, \(featureCounts.count) features, \(settingCounts.count) settings placed once")
    }
}
