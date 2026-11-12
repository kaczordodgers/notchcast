import Foundation

extension NotchcastFeature.BackupKeys {
    static let aiUsage = Self(allowed: [:], excluded: [
        NotchcastPreferences.aiUsageGatewayKey,
    ])
}
