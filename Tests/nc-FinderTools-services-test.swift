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
// notchcast-sources: Tinycast/Features/FinderTools/FinderToolsCoordinator+Registration.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastRegistrant.swift
// notchcast-kit: platform
import Foundation
import CoreGraphics

enum Paster {
    static let tinycastEventTag: Int64 = 0x54494E59
}

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let feature: NotchcastFeature?
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

@MainActor final class AppCore {}

@main @MainActor
struct FinderToolsServicesTest {
    static func main() {
        let hub = EventTapHub()
        let coordinator = FinderToolsCoordinator(hub: hub)
        coordinator.cut()
        coordinator.paste()
        coordinator.rename()
        precondition(hub.consumerCount == 0)
        precondition(FinderCommandService.originalKey(for: .cut)?.0 == 7)
        precondition(FinderCommandService.originalKey(for: .paste)?.0 == 9)
        precondition(FinderCommandService.originalKey(for: .rename)?.0 == 15)
        let hyper: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        precondition(FinderCommandService.originalKey(for: .rename)?.1 == hyper)
        precondition(FinderCommandService.originalKey(for: .forget) == nil)
        let entries = FinderToolsCoordinator.register(AppCore())
        precondition(entries.map(\.requires) == [[.finderCutPaste], [.finderRename]])
        precondition(entries.allSatisfy { $0.requiresAny.isEmpty && $0.module is FinderToolsModule })
        precondition(entries[0].module !== entries[1].module)
        print("PASS: shipped Finder services compile in Swift 6; disabled commands have no effects")
        print("PASS: registration returns one module per switch, each requiring its own feature")
    }
}
