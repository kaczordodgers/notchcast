import Foundation

extension NotchcastFeature.BackupKeys {
    static let aiUsage = Self(allowed: [:], excluded: [
        NotchcastPreferences.aiUsageCachePathKey,
        NotchcastPreferences.aiUsageGatewayKey,
    ])
}
