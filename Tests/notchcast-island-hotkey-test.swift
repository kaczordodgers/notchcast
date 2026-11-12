// notchcast-sources: Tinycast/Features/HotKeys/Model/DoubleTapModifier.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/ModifierKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyBinding.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HyperKey.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HIDKeyMapping.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/HotKeys/Service/KeyShortcut.swift
// notchcast-sources: Tinycast/Features/HotKeys/Service/HotKeyManager.swift
// notchcast-sources: Tinycast/Platform/ASCIIKeyboardLayout.swift
// notchcast-sources: Tests/[Hh]ot[Kk]ey*[Dd]ispatch*[Ff]ixtures.swift
// notchcast-kit: core command
// notchcast-sources: Tinycast/Features/Notchcast/Launcher/NotchcastCommandCatalog.swift
// notchcast-sources: Tinycast/Features/Notchcast/Pages/IslandInputState.swift
// notchcast-sources: Tinycast/Features/Notchcast/Island/HotKeyManager+IslandToggle.swift
import Carbon.HIToolbox
import Foundation

@MainActor final class AppCore {
    static let shared = AppCore()
    var paletteCoordinator: AppCore { self }
    var isVisible = false
    func hidePalette(restoreFocus: Bool) {}
}
extension NotchcastCommandCatalog {
    nonisolated(unsafe) static var all: [NotchcastCommand] = []
}

/// Toggle Island's Hyper+S default and the pinned state the command opens into.
@main
@MainActor
struct IslandHotKeyTest {
    static func main() {
        let toggle = NotchcastCommand(slug: "toggle-island", name: "Toggle Island", sfSymbol: "test", feature: .island,
                                      legacyID: "command:toggle-island", run: {})
        let other = NotchcastCommand(slug: "other", name: "Other", sfSymbol: "test", feature: .island, run: {})
        NotchcastCommandCatalog.all = [toggle, other]
        let action = HotKeyAction.notchcastCommand(entryID: toggle.entry.id)
        let hyperS = combo(cmdKey | controlKey | optionKey | shiftKey)

        withManager { manager, marker in
            manager.seedIslandToggle(commandID: toggle.entry.id, marker: marker)
            precondition(manager.binding(for: action) == hyperS, "a fresh install binds Hyper+S to Toggle Island")
            manager.setBinding(nil, for: action)
            manager.seedIslandToggle(commandID: toggle.entry.id, marker: marker)
            precondition(manager.binding(for: action) == nil, "a cleared shortcut is not seeded again")
        }
        withManager { manager, marker in
            let own = combo(cmdKey | optionKey)
            manager.setBinding(own, for: action)
            manager.seedIslandToggle(commandID: toggle.entry.id, marker: marker)
            precondition(manager.binding(for: action) == own, "the user's own shortcut stays")
        }
        withManager { manager, marker in
            let otherAction = HotKeyAction.notchcastCommand(entryID: other.entry.id)
            manager.setBinding(hyperS, for: otherAction)
            manager.seedIslandToggle(commandID: toggle.entry.id, marker: marker)
            precondition(manager.binding(for: action) == nil, "a taken chord is left to its owner")
            precondition(manager.binding(for: otherAction) == hyperS)
        }
        KeyShortcut.displayedHyperChord = { [.control, .option, .command] }
        withManager { manager, marker in
            manager.seedIslandToggle(commandID: toggle.entry.id, marker: marker)
            precondition(manager.binding(for: action) == combo(cmdKey | controlKey | optionKey),
                         "a Hyper key without Shift gets its own chord")
        }
        pinnedToggle()
        print("notchcast-island-hotkey: Hyper+S seeds once, never over a user's choice; Toggle Island opens pinned")
    }

    /// `IslandController.toggle`: open, then pin; only Escape, a page key or the command again closes it.
    static func pinnedToggle() {
        var state = IslandInputState()
        state.setPinned(true)
        precondition(!state.isPinned, "an island that could not open is not pinned")
        state.open()
        state.setPinned(true)
        state.dismiss(.appSwitch)
        precondition(state.isOpen, "another app taking focus leaves it open")
        state.dismiss(.outsideClick)
        precondition(state.isOpen, "a click elsewhere leaves it open")
        state.pointer(inside: true, now: 0, hoverEnabled: true, delay: 0.1)
        state.pointer(inside: false, now: 1, hoverEnabled: true, delay: 0.1)
        precondition(state.pendingHover == nil && state.advance(now: 5) == nil && state.isOpen,
                     "the pointer leaving leaves it open")
        state.dismiss(.escape)
        precondition(!state.isOpen && !state.isPinned, "Escape closes it")
    }

    static func combo(_ modifiers: Int) -> HotKeyBinding {
        .combo(KeyShortcut(carbonKeyCode: kVK_ANSI_S, carbonModifiers: modifiers))
    }

    /// The hook runs once `hotKeys.start` has loaded the stored bindings.
    static func withManager(_ body: (HotKeyManager, UserDefaults) -> Void) {
        let domain = "notchcast.island-hotkey-test.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let manager = HotKeyManager(defaults: defaults)
        manager.start(customCommandIDs: [], quicklinkIDs: [], windowLayoutIDs: [],
                      windowRoomIDs: [], customWindowSizeIDs: [], quickActionIDs: [])
        body(manager, defaults)
    }
}
