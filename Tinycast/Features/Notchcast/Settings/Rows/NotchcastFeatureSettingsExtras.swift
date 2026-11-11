import SwiftUI

/// What one feature adds to its generic Settings rows.
@MainActor
struct NotchcastFeatureSettingsExtras {
    var detail: String?
    /// Its rows read services `NotchcastCore.start` creates; the offscreen gallery never starts them.
    var needsServices = false
    var label: AnyView?
    var rows: AnyView?
    var enabledRows: AnyView?
}

extension NotchcastFeature {
    @MainActor var settingsExtras: NotchcastFeatureSettingsExtras {
        switch self {
        case .dockTweaks: .dockTweaks
        case .cleaningMode: .cleaningMode
        case .cleanAIData: .cleanAIData
        case _ where NotchcastFeature.batteryModule.contains(self): .battery(self)
        case .microphoneMute: .microphoneMute
        case .inUseMarks: .inUseMarks
        case .spotifyConnect: .spotifyConnect
        case .settingsBackup: .settingsBackup
        case .shelfBetweenMacs: .shelfBetweenMacs
        default: .init()
        }
    }
}

private extension NotchcastFeatureSettingsExtras {
    static var cleanAIData: Self {
        Self(detail: String(localized: "Codex and OpenCode are report-only.", table: "Notchcast"))
    }

    static var settingsBackup: Self {
        let coordinator = ForkSettingsBackupCoordinator.shared
        guard coordinator.choosing else { return Self() }
        return Self(rows: AnyView(
            ForkSettingsBackupCopiesView(copies: coordinator.copies, restore: { coordinator.restore(name: $0) })
                .onDisappear { coordinator.cancelChoosing() }))
    }
}
