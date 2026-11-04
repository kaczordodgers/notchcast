import CryptoKit
import Foundation

nonisolated enum TweakProfile {
    enum Failure: Error { case unknownSelection }

    static func data(bundleIdentifier: String, keepingAI: Set<String>?, privacy: Set<String>) throws -> Data {
        guard keepingAI?.isSubset(of: Set(AIOffCatalog.features.map(\.id))) != false,
              privacy.isSubset(of: Set(PrivacyCatalog.restrictions.keys).union(PrivacyCatalog.preferences.keys))
        else { throw Failure.unknownSelection }
        let identifier = bundleIdentifier + ".tweaks"
        func payload(_ type: String, _ suffix: String) -> [String: Any] {
            let name = identifier + "." + suffix
            var hash = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
            hash[6] = (hash[6] & 15) | 0x50
            hash[8] = (hash[8] & 63) | 0x80
            let uuid = UUID(uuid: (hash[0], hash[1], hash[2], hash[3], hash[4], hash[5],
                                   hash[6], hash[7], hash[8], hash[9], hash[10], hash[11],
                                   hash[12], hash[13], hash[14], hash[15])).uuidString
            return ["PayloadType": type, "PayloadVersion": 1, "PayloadIdentifier": name,
                    "PayloadUUID": uuid]
        }
        var restrictions = payload("com.apple.applicationaccess", "restrictions")
        var forced: [String: [String: Any]] = [:]
        func force(_ preferences: [(TweakPreference, TweakValue)]) {
            for (preference, value) in preferences { forced[preference.domain, default: [:]][preference.key] = value.object }
        }
        if let kept = keepingAI {
            for feature in AIOffCatalog.features where !kept.contains(feature.id) {
                for key in feature.restrictions { restrictions[key] = false }
                force(feature.preferences)
            }
            for model in AIOffCatalog.removableModels(keeping: kept) {
                if let asset = AIOffCatalog.assetTypes[model] {
                    forced["com.apple.MobileAsset", default: [:]]["DownloadServerBaseURLOverride-" + asset]
                        = "https://127.0.0.1:9/"
                }
            }
        }
        for id in privacy {
            if let key = PrivacyCatalog.restrictions[id] { restrictions[key] = false }
            force(PrivacyCatalog.preferences[id] ?? [])
        }
        var contents: [[String: Any]] = restrictions.count > 4 ? [restrictions] : []
        for domain in forced.keys.sorted() {
            var item = payload("com.apple.ManagedClient.preferences", domain)
            item["PayloadContent"] = [domain: ["Forced": [["mcx_preference_settings": forced[domain] ?? [:]]]]]
            contents.append(item)
        }
        var profile = payload("Configuration", "profile")
        profile["PayloadIdentifier"] = identifier
        profile["PayloadScope"] = "System"
        profile["PayloadRemovalDisallowed"] = false
        profile["PayloadContent"] = contents
        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }
}
