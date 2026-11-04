// notchcast-sources: Tinycast/Features/FinderTools/Model/*.swift
// notchcast-sources: Tinycast/Features/FinderTools/Service/*.swift
// notchcast-sources: Tinycast/Features/FinderTools/UI/FinderToolsCoordinator.swift
// notchcast-sources: Tinycast/Features/FinderTools/FinderToolsModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Input/*.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastPreferences.swift
// notchcast-sources: Tinycast/Features/FinderTools/UI/FinderToolsCoordinator+Commands.swift
// notchcast-sources: Tinycast/Platform/NotificationToken.swift
import Foundation
import CoreGraphics

enum Paster {
    static let tinycastEventTag: Int64 = 0x54494E59
}

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

@MainActor enum NotchcastCore {
    static let finderTools = FinderToolsCoordinator(hub: EventTapHub())
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
        precondition(NotchcastFeature.finderCutPaste.settingsGroup == .finder)
        precondition(NotchcastFeature.finderRename.settingsGroup == .finder)
        precondition(FinderCommandService.originalKey(for: .cut)?.0 == 7)
        precondition(FinderCommandService.originalKey(for: .paste)?.0 == 9)
        precondition(FinderCommandService.originalKey(for: .rename)?.0 == 15)
        let hyper: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        precondition(FinderCommandService.originalKey(for: .rename)?.1 == hyper)
        precondition(FinderCommandService.originalKey(for: .forget) == nil)
        precondition([FinderToolsCoordinator.cutCommand.slug, FinderToolsCoordinator.pasteCommand.slug,
                      FinderToolsCoordinator.renameCommand.slug] == ["finder-cut", "finder-paste", "finder-rename"])
        print("PASS: shipped Finder services compile in Swift 6; disabled commands have no effects")
    }
}
