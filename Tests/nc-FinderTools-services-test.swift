// notchcast-sources: Tinycast/Features/FinderTools/Model/*.swift
// notchcast-sources: Tinycast/Features/FinderTools/Service/*.swift
// notchcast-sources: Tinycast/Features/FinderTools/UI/FinderToolsCoordinator.swift
// notchcast-sources: Tinycast/Features/FinderTools/FinderToolsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Input/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import Foundation

enum Paster {
    static let tinycastEventTag: Int64 = 0x54494E59
}

@main @MainActor
struct FinderToolsServicesTest {
    static func main() {
        for feature in [NotchcastFeature.finderCutPaste, .finderRename] {
            precondition(feature.requiredGrants == [.accessibility])
            precondition(!feature.needsIsland)
        }
        let hub = EventTapHub()
        let coordinator = FinderToolsCoordinator(hub: hub)
        coordinator.cut()
        coordinator.paste()
        coordinator.rename()
        precondition(hub.consumerCount == 0)
        precondition(coordinator.cutSession.fileCount == 0)
        precondition(coordinator.lastMoveFileCount == 0)
        print("PASS: shipped Finder services compile in Swift 6; disabled commands have no effects")
    }
}
