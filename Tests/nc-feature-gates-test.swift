// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature*.swift
// notchcast-sources: Tinycast/Features/Settings/SettingsTab.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSettings*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Settings/Tree/NotchcastSetting.swift
import Foundation

/// A feature row is greyed while any feature it is gated on is off
/// (`NotchcastModuleSettingsView`: the Island gate via `needsIsland`, then `dependencies`).
/// A switch gated on itself, directly or through a chain, can never be turned back on.
@main
struct NotchcastFeatureGatesTests {
    static func gates(_ feature: NotchcastFeature) -> [NotchcastFeature] {
        feature.dependencies + (feature.needsIsland ? [.island] : [])
    }

    static func main() {
        var failures: [String] = []
        for feature in NotchcastFeature.allCases {
            var seen: Set<NotchcastFeature> = []
            var queue = gates(feature)
            while let next = queue.popLast() {
                guard seen.insert(next).inserted else { continue }
                queue += gates(next)
            }
            if seen.contains(feature) { failures.append("\(feature)") }
        }
        guard failures.isEmpty else {
            FileHandle.standardError.write(Data("FAIL: switches gated on their own state: \(failures)\n".utf8))
            exit(1)
        }
        precondition(!NotchcastFeature.island.needsIsland, "the Island switch must stay usable while Island is off")
        print("PASS: no feature switch is gated on its own state (\(NotchcastFeature.allCases.count) features)")
    }
}
