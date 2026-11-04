import Foundation

nonisolated enum AIOffDaemonPlan {
    enum Group: String, CaseIterable, Sendable {
        case intelligence, knowledge, photos, siri, tips, screenTime, gameCenter, mediaKeys

        var labels: [String] {
            let names: [String] = switch self {
            case .intelligence:
                ["Siri.agent", "assistantd", "assistant_service", "assistant_cdmd", "siriactionsd",
                 "siriappintentsd", "siriinferenced", "sirittsd", "SiriTTSTrainingAgent", "campo",
                 "generativeexperiencesd", "intelligencecontextd", "intelligenceflowd",
                 "intelligenceplatformd", "intelligencetasksd", "visualintelligenced",
                 "GenerativeFunctions.agentstored", "ModelCatalogAgent"]
            case .knowledge:
                ["knowledge-agent", "knowledgeconstructiond", "siriknowledged", "spotlightknowledged",
                 "spotlightknowledged.importer", "spotlightknowledged.updater", "duetexpertd"]
            case .photos: ["mediaanalysisd", "photoanalysisd"]
            case .siri: ["assistantd", "siriknowledged"]
            case .tips: ["tipsd"]
            case .screenTime: ["ScreenTimeAgent", "UsageTrackingAgent"]
            case .gameCenter: ["gamed"]
            case .mediaKeys: ["rcd"]
            }
            return names.map { "com.apple." + $0 }
        }
    }

    static func commands(_ group: Group, uid: UInt32, restoring: Bool = false) -> [TweakCommand] {
        group.labels.map {
            TweakCommand(executable: "/bin/launchctl",
                         arguments: [restoring ? "enable" : "disable", "gui/\(uid)/\($0)"])
        }
    }

    static func commands(featureID: String, uid: UInt32, restoring: Bool = false) throws -> [TweakCommand] {
        guard AIOffCatalog.features.contains(where: { $0.id == featureID }) else {
            throw AIOffModelService.Failure.unknownFeature
        }
        // Shared inference agents must remain available while any dependent feature is kept.
        return featureID == "siri" ? commands(.siri, uid: uid, restoring: restoring) : []
    }
}
