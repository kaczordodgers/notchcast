// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettings*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSetting.swift
import Foundation

@main
struct NotchcastSettingsTreeTests {
    static func main() throws {
        precondition(!NotchcastFeature.agentAnswer.isWired, "Settings and search exclude unwired features")
        let modules = NotchcastSettingsModule.allCases
        precondition(modules.count == 17, "Expected 17 modules")
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
        let dispatchSources = try ["A", "B", "C", "D"].map { suffix in
            try String(contentsOfFile:
                "Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettingRows+\(suffix).swift",
                encoding: .utf8)
        }.joined(separator: "\n")
        for setting in NotchcastSetting.allCases {
            let marker = "case .\(setting.rawValue):"
            precondition(dispatchSources.components(separatedBy: marker).count == 2,
                         "Setting dispatch must appear once: \(setting)")
            let arm = dispatchSources.components(separatedBy: marker)[1]
                .components(separatedBy: "case ")[0].components(separatedBy: "default:")[0]
            precondition(arm.contains("SettingRow(" ) && !arm.contains("EmptyView"),
                         "Empty setting dispatch: \(setting)")
        }
        precondition(NotchcastSettingsModule.island.tab == .notchcast, "Legacy Island tab")
        precondition(NotchcastSettingsModule.island.slug == "notchcast", "Legacy Island slug")
        precondition(NotchcastSettingsModule(tab: .general) == nil, "Upstream tab rejected")
        precondition(
            SettingsSection.notchcast.tabs == modules.map(\.tab),
            "Section owns every module in order")
        precondition(modules.allSatisfy { !$0.visibleGroups.isEmpty }, "Every sidebar page has visible rows")
        precondition(NotchcastSettingsModule.module(of: .katana) == .musicAndSound)
        precondition(NotchcastSettingsModule.module(of: .treadmillWalk) == .monitorAndFans)
        precondition(NotchcastSettingsModule.module(of: .treadmillHistory) == .monitorAndFans)
        for feature: NotchcastFeature in [.katana, .treadmillWalk, .treadmillHistory] where feature.isWired {
            let module = NotchcastSettingsModule.module(of: feature)
            precondition(module.visibleGroups.contains { $0.items.contains { $0.feature == feature } })
        }
        precondition(!SettingsSection.features.tabs.contains(.notchcast), "Island moved out of Features")
        var strings: [String: [String: Any]] = [:]
        for table in ["Localizable", "Notchcast"] {
            let data = try Data(contentsOf: URL(filePath: "Tinycast/Resources/\(table).xcstrings"))
            let catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let entries = catalog?["strings"] as? [String: [String: Any]] else {
                fatalError("Missing string catalog: \(table)")
            }
            strings.merge(entries) { current, _ in current }
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
