#if DEBUG
import AppKit

/// The resting pill's scenes: they run before the launcher opens, so the pill stays at rest.
@MainActor
enum IslandPillScenes {
    static let names: Set = ["install-report",
                             "pill-menu", "pill-settings", "glance", "glance-menu", "pill-menu-quiet", "pill-settings-quiet",
                             "glance-modal", "pill-busy", "window-guard-new", "window-guard-raise",
                             "window-guard-deferred", "island-ax", "update", "notice-queue",
                             "notice-unseen", "pill-menu-rows", "capture-sharing", "dictation", "dictation-notch",
                             "dictation-away", "dictation-away-notch"]

    static func run(_ scene: String, core: AppCore, screen: NSScreen) async {
        if scene == "dictation-notch" || scene == "dictation-away-notch" {
            IslandController.simulatedNotch = DictationIslandScenes.notch
        }
        core.island.start()
        await IslandVerification.pause(0.6)
        if scene == "capture-sharing" {
            // Holding no pill here lets the scene prove a replaced one is released.
            await IslandCaptureScenes.run(core: core)
            IslandScenes.pass(scene, screen: screen)
            _exit(0)
        }
        guard let controller = core.island.resting else { IslandVerification.require(false, "resting pill"); return }
        var waited = 0.6
        while !controller.acceptsClicks, waited < 2.5 { await IslandVerification.pause(0.05); waited += 0.05 }
        print("PILL_READY clicks=\(controller.acceptsClicks) after=\(waited)s")
        IslandVerification.require(controller.acceptsClicks, "pill accepts clicks before the readiness timeout")
        IslandVerification.require(screen.frame.contains(controller.backdropWindow.frame), "pill on test display")
        switch scene {
        case "pill-menu": await menu(core: core, controller: controller)
        case "pill-menu-rows": await IslandMenuRowScenes.run(core: core, controller: controller)
        case "pill-settings": await settings(core: core, controller: controller)
        case "glance-menu": await glanceMenu(core: core, controller: controller)
        case "pill-menu-quiet": await quietMenu(core: core, controller: controller, screen: screen)
        case "pill-settings-quiet": await quietSettings(core: core, controller: controller)
        case "glance-modal": await glanceModal(core: core, controller: controller, screen: screen)
        case "pill-busy": await busy(core: core, controller: controller)
        case "window-guard-new", "window-guard-raise", "window-guard-deferred":
            await IslandWindowScenes.windowGuard(core: core, scene: scene)
        case "island-ax": await IslandAccessibilityScenes.run(core: core, controller: controller)
        case "update": await IslandUpdateScenes.run(core: core, controller: controller)
        case "install-report": await IslandInstallReportScenes.run(core: core, controller: controller)
        case "notice-queue": await IslandNoticeScenes.run(core: core, controller: controller)
        case "notice-unseen": await IslandNoticeScenes.unseen(core: core, controller: controller)
        case "dictation", "dictation-notch", "dictation-away", "dictation-away-notch":
            await DictationIslandScenes.run(scene: scene, core: core, controller: controller)
        default: await glance(core: core, controller: controller)
        }
        IslandScenes.pass(scene, screen: screen)
        _exit(0)
    }

    static var menuPanel: MenuPanel? { NSApp.windows.first { $0 is MenuPanel && $0.isVisible } as? MenuPanel }
    static var paletteVisible: Bool { NSApp.windows.contains { $0 is PalettePanel && $0.isVisible } }
    static var statusItemWindows: Int {
        NSApp.windows.filter { String(describing: type(of: $0)).contains("StatusBar") }.count
    }

    static func openMenu(_ controller: IslandController, _ type: NSEvent.EventType,
                                 modifiers: NSEvent.ModifierFlags = [], _ label: String) async -> MenuPanel? {
        controller.clickBackdrop(type, modifiers: modifiers)
        await IslandVerification.pause(0.35)
        guard let menu = menuPanel else { IslandVerification.require(false, "\(label) opens the pill menu"); return nil }
        IslandVerification.require(!paletteVisible, "\(label) leaves the launcher closed")
        IslandVerification.require(menu.parent === controller.backdropWindow, "\(label) hangs the menu on the island")
        IslandVerification.require(menu.isKeyWindow, "\(label) menu takes key for typing")
        return menu
    }

    private static func closeMenu(_ menu: MenuPanel, _ label: String) async {
        IslandLatency.key(menu, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.35)
        IslandVerification.require(menuPanel == nil, "\(label) Escape closes the pill menu")
    }

    /// The meeting-free menu hangs under the pill, ends in Quit, and is captured on its layer.
    private static func requireRestMenu(_ menu: MenuPanel, core: AppCore, controller: IslandController) async {
        guard let pill = controller.pillFrame else { IslandVerification.require(false, "pill frame"); return }
        let pillBottom = controller.backdropWindow.frame.maxY - pill.maxY
        print("PILL \(pill) BOTTOM \(pillBottom) MENU \(menu.frame)")
        IslandVerification.require(menu.frame.maxY <= pillBottom + 0.5, "menu sits below the pill")
        IslandVerification.require(pillBottom - menu.frame.maxY < 40, "menu hangs right under the pill")
        let titles = core.island.pillMenu.itemTitles
        print("MENU_ROWS \(titles)")
        IslandVerification.require(titles.last == CommandID.quit.name, "Quit closes the pill menu")
        IslandVerification.require(titles.contains(String(localized: "Settings…")), "pill menu offers Settings")
        IslandVerification.require(!titles.contains { $0.hasPrefix(String(localized: "Join \("")")) },
                                   "no meeting, no join row")
        await controller.capture("pill-menu")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured.contains("pill-menu"), "pill menu layer capture")
    }

    private static func menu(core: AppCore, controller: IslandController) async {
        guard let menu = await openMenu(controller, .rightMouseDown, "right-click") else { return }
        await requireRestMenu(menu, core: core, controller: controller)
        for character in "zzzz" { IslandLatency.key(menu, code: 6, characters: String(character)) }
        await IslandVerification.pause(0.2)
        IslandVerification.require(core.island.pillMenu.itemTitles.isEmpty, "typing filters the pill menu")
        IslandLatency.key(menu, code: 53, characters: "\u{1b}")
        await IslandVerification.pause(0.2)
        IslandVerification.require(menuPanel != nil && core.palette.menuQuery.isEmpty, "first Escape clears the search")
        await closeMenu(menu, "right-click")
        for (modifier, label) in [(NSEvent.ModifierFlags.control, "control-click"), (.option, "option-click")] {
            guard let again = await openMenu(controller, .leftMouseDown, modifiers: modifier, label) else { return }
            await closeMenu(again, label)
        }
        controller.clickBackdrop(.rightMouseDown)
        await IslandVerification.pause(0.35)
        guard let reopened = menuPanel else { IslandVerification.require(false, "menu reopens"); return }
        IslandLatency.key(reopened, code: 43, characters: ",", modifiers: .command)
        await IslandVerification.pause(0.6)
        IslandVerification.require(menuPanel == nil, "Command-comma closes the pill menu")
        IslandVerification.require(settingsWindow?.isVisible == true, "Command-comma opens Settings")
        IslandVerification.require(statusItemWindows == 0, "no menu bar item exists")
    }

    static var settingsWindow: NSWindow? {
        NSApp.windows.first { $0.frameAutosaveName == "SettingsWindow" }
    }

    private static func settings(core: AppCore, controller: IslandController) async {
        guard let menu = await openMenu(controller, .rightMouseDown, "right-click") else { return }
        let settings = String(localized: "Settings…")
        for character in settings.prefix(5) { IslandLatency.key(menu, code: 0, characters: String(character)) }
        await IslandVerification.pause(0.2)
        IslandVerification.require(core.island.pillMenu.itemTitles.first == settings, "search finds Settings")
        IslandLatency.key(menu, code: 36, characters: "\r")
        await IslandVerification.pause(0.8)
        guard let window = settingsWindow, window.isVisible else {
            IslandVerification.require(false, "Return on Settings opens Settings"); return
        }
        IslandVerification.require(statusItemWindows == 0, "no menu bar item exists")
        for tab in [SettingsTab.general, .calendar] {
            core.settingsCoordinator.showSettings(tab: tab)
            await IslandVerification.pause(0.7)
            still(window, name: "settings-\(tab.slug)")
        }
    }

    static func still(_ window: NSWindow, name: String) {
        guard let output = ProcessInfo.processInfo.environment["ISLAND_OUTPUT"],
              let view = window.contentView?.superview ?? window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            IslandVerification.require(false, "\(name) bitmap allocated"); return
        }
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            IslandVerification.require(false, "\(name) PNG encoding"); return
        }
        do { try data.write(to: URL(filePath: output + "/" + name + ".png")) } catch {
            IslandVerification.require(false, "\(name) PNG write \(error)")
        }
        print("CAPTURE \(name) WINDOW \(window.frame)")
    }

    /// A synthetic Zoom meeting four minutes out, carded through the Debug preview.
    static func previewMeeting(core: AppCore) async -> MeetingEvent {
        let now = Date()
        let meeting = MeetingEvent(id: "glance", title: "Weekly product sync", start: now + 4 * 60,
            end: now + 34 * 60, isAllDay: false, isDeclined: false, calendarID: "c", calendarName: "Work",
            calendarColor: nil, calendarItemID: "i", link: MeetingLink.detect(in: "https://us02web.zoom.us/j/123456789"))
        core.island.glance.preview(meeting, now: now)
        await IslandVerification.pause(0.9)
        return meeting
    }

    /// Sends no input, so it stays valid while another app's window covers the pill.
    private static func glance(core: AppCore, controller: IslandController) async {
        let rest = controller.outlineBounds.width
        _ = await previewMeeting(core: core)
        let width = controller.outlineBounds.width
        print("GLANCE rest=\(rest) width=\(width) target=\(controller.glanceWidthTarget) title=\(controller.showsGlanceTitle)")
        IslandVerification.require(width > rest + 1, "the glance widens the pill")
        IslandVerification.require(abs(width - controller.glanceWidthTarget) < 0.5, "the pill settles at the glance width")
        let font = NotchTheme.Typography.islandGlanceNSFont
        let digits = Set("0123456789".map { NSAttributedString(string: String($0), attributes: [.font: font]).size().width })
        print("GLANCE digit widths=\(digits.sorted())")
        IslandVerification.require(digits.count == 1, "every digit in the island font is the same width")
        await controller.capture("glance")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured.contains("glance"), "glance layer capture")
    }

    private static func glanceMenu(core: AppCore, controller: IslandController) async {
        let meeting = await previewMeeting(core: core)
        guard let menu = await openMenu(controller, .rightMouseDown, "glance right-click") else { return }
        let titles = core.island.pillMenu.itemTitles
        print("MENU_ROWS \(titles)")
        IslandVerification.require(titles.first == String(localized: "Join \(MenuBarSummary.title(meeting.title))"),
                                   "a carded meeting leads the menu with Join")
        await controller.capture("pill-menu-meeting")
        await IslandVerification.pause(0.3)
        IslandVerification.require(controller.captured.contains("pill-menu-meeting"), "meeting menu layer capture")
        await closeMenu(menu, "glance")
        controller.clickBackdrop(.leftMouseDown)
        await IslandVerification.pause(0.4)
        IslandVerification.require(!paletteVisible, "a click on the glance never opens the launcher (#884)")
        IslandVerification.require(menuPanel == nil && core.island.hover.isOpen,
                                   "a click on the glance opens the island, never its menu (#1029)")
        core.island.hover.togglePin()
    }

    /// A modal that hid the carded pill must not leave it hidden once the launcher has closed.
    private static func glanceModal(core: AppCore, controller: IslandController, screen: NSScreen) async {
        _ = await previewMeeting(core: core)
        let backdrop = controller.backdropWindow
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.6)
        IslandVerification.require(paletteVisible && backdrop.isVisible, "the launcher opens over the glance")
        let picker = IslandWindowScenes.PinnedOpenPanel()
        picker.testScreen = screen.frame
        picker.setFrame(CGRect(x: screen.frame.midX - 300, y: screen.frame.midY - 200, width: 600, height: 400),
                        display: false)
        let probe = IslandWindowScenes.ModalProbe {
            IslandVerification.require(NSApp.modalWindow === picker && !backdrop.isVisible, "the modal hides the island")
            core.paletteCoordinator.hidePalette(restoreFocus: false)
            controller.closed()
            IslandVerification.require(!paletteVisible && !backdrop.isVisible, "the launcher closes during the modal")
            picker.cancel(nil)
        }
        probe.perform(#selector(IslandWindowScenes.ModalProbe.check), with: nil, afterDelay: 0.5,
                      inModes: [.modalPanel, .common])
        NSApp.activate()
        IslandVerification.require(picker.runModal() == .cancel, "the modal ends")
        await IslandVerification.pause(0.3)
        let content = controller.contentKey ?? "nil"
        print("GLANCE_MODAL content=\(content) backdropVisible=\(backdrop.isVisible) palette=\(paletteVisible)")
        IslandVerification.require(!paletteVisible && controller.contentKey == "glance", "the glance returns to rest")
        IslandVerification.require(backdrop.isVisible, "the carded pill is visible after the modal ends")
    }

    /// The pill menu opens only from a resting pill: never over the launcher, nor while it closes.
    private static func busy(core: AppCore, controller: IslandController) async {
        let rest = controller.outlineBounds
        core.paletteCoordinator.showPalette(mode: .launcher)
        await IslandVerification.pause(0.6)
        IslandVerification.require(paletteVisible, "the launcher is open")
        for (type, modifiers, label) in [(NSEvent.EventType.rightMouseDown, NSEvent.ModifierFlags(), "right-click"),
                                         (.leftMouseDown, .control, "control-click"), (.leftMouseDown, .option, "option-click")] {
            controller.clickBackdrop(type, modifiers: modifiers)
            await IslandVerification.pause(0.2)
            IslandVerification.require(menuPanel == nil, "\(label) over the open launcher opens no menu")
        }
        IslandVerification.require(!(controller.backdropWindow.contentView?.accessibilityPerformShowMenu() ?? true),
                                   "show-menu over the open launcher is refused")
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        let closing = controller.outlineBounds
        controller.clickBackdrop(.rightMouseDown)
        print("CLOSING rest=\(rest) atClick=\(closing) palette=\(paletteVisible)")
        IslandVerification.require(closing.height > rest.height + 1, "the right-click lands mid-close")
        await IslandVerification.pause(0.2)
        IslandVerification.require(menuPanel == nil, "right-click during the closing transition opens no menu")
        var waited = 0.0
        while controller.outlineBounds != rest, waited < 2 {
            await IslandVerification.pause(0.1)
            waited += 0.1
        }
        print("SETTLE outline=\(controller.outlineBounds) after=\(waited)s")
        IslandVerification.require(controller.outlineBounds == rest, "the pill settles back at rest")
        guard let menu = await openMenu(controller, .rightMouseDown, "right-click at rest") else { return }
        await closeMenu(menu, "right-click at rest")
    }

    /// Opens the menu through the pill's own callback, so no event is synthesized.
    private static func quietOpen(_ controller: IslandController) async -> MenuPanel? {
        guard let pill = controller.pillFrame else { IslandVerification.require(false, "pill frame"); return nil }
        controller.onMenu?(pill, controller.backdropWindow)
        await IslandVerification.pause(0.35)
        guard let menu = menuPanel else { IslandVerification.require(false, "quiet open shows the pill menu"); return nil }
        IslandVerification.require(!paletteVisible, "the menu leaves the launcher closed")
        IslandVerification.require(menu.parent === controller.backdropWindow, "the menu hangs on the island")
        IslandVerification.require(menu.isKeyWindow, "the menu takes key")
        return menu
    }

    private static func quietMenu(core: AppCore, controller: IslandController, screen: NSScreen) async {
        guard let menu = await quietOpen(controller) else { return }
        await requireRestMenu(menu, core: core, controller: controller)
        IslandVerification.require(statusItemWindows == 0, "no menu bar item exists")
        core.palette.menuQuery = "zzzz"
        await IslandVerification.pause(0.2)
        IslandVerification.require(core.island.pillMenu.itemTitles.isEmpty, "a query filters the pill menu")
        core.palette.menuQuery = ""
        await IslandVerification.pause(0.2)
        IslandVerification.require(core.island.pillMenu.isObservingResign, "the menu watches its resign-key")
        let other = NSPanel(contentRect: CGRect(x: screen.visibleFrame.midX - 100, y: screen.visibleFrame.minY + 40,
            width: 200, height: 80), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.makeKeyAndOrderFront(nil)
        let closedAtResign = menuPanel == nil
        print("RESIGN other.key=\(other.isKeyWindow) closedBeforeYield=\(closedAtResign)")
        IslandVerification.require(other.isKeyWindow, "another own window takes key")
        IslandVerification.require(closedAtResign, "the menu closes on resign-key before the stock path yields")
        IslandVerification.require(!core.island.pillMenu.isObservingResign, "hide removes the resign observer")
        await IslandVerification.pause(0.3)
        IslandVerification.require(menuPanel == nil && core.palette.menuQuery.isEmpty, "the menu stays closed")
        other.close()
    }

    private static func quietSettings(core: AppCore, controller: IslandController) async {
        guard await quietOpen(controller) != nil else { return }
        core.island.pillMenu.activate(title: String(localized: "Settings…"))
        await IslandVerification.pause(0.8)
        IslandVerification.require(menuPanel == nil, "the Settings row closes the pill menu")
        guard let window = settingsWindow, window.isVisible else {
            IslandVerification.require(false, "the Settings row opens Settings"); return
        }
        IslandVerification.require(statusItemWindows == 0, "Settings opens with no menu bar item")
        print("SETTINGS \(window.frame) TEST \(IslandVerification.testScreen?.frame ?? .null)")
        IslandVerification.require(IslandVerification.testScreen?.frame.contains(window.frame) == true,
                                   "Settings opens on the test display")
        let hidden = ["Show in menu bar", "Show in Menu Bar", "Calendar in Menu Bar", "Show Upcoming Events",
                      "Only show events with meetings", "Hide when there are no upcoming events", "Hide Current Event"]
        let panes: [(SettingsTab, String)] = [(.general, "Launch at login"), (.calendar, "Days to Show")]
        IslandVerification.require(wakeAccessibilityTree(), "the app's own AX tree answers")
        await IslandVerification.pause(0.3)
        for (tab, shown) in panes {
            core.settingsCoordinator.showSettings(tab: tab)
            await IslandVerification.pause(0.7)
            var texts: [String] = []
            accessibilityTexts(window.contentView as Any, depth: 0, into: &texts)
            let leaked = hidden.filter { key in
                let title = String(localized: String.LocalizationValue(key))
                return texts.contains { $0.contains(title) }
            }
            print("PANE \(tab.slug) texts=\(texts.count) leaked=\(leaked)")
            IslandVerification.require(texts.contains { $0.contains(String(localized: String.LocalizationValue(shown))) },
                                       "\(tab.slug) pane reads \(shown)")
            IslandVerification.require(leaked.isEmpty, "\(tab.slug) pane hides the menu-bar rows")
            still(window, name: "settings-\(tab.slug)")
        }
    }

    /// SwiftUI builds its accessibility nodes only once an AX client has asked, so ask ourselves.
    private static func wakeAccessibilityTree() -> Bool {
        var windows: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(AXUIElementCreateApplication(getpid()),
                                                   kAXWindowsAttribute as CFString, &windows)
        print("AXWAKE result=\(result.rawValue) windows=\((windows as? [Any])?.count ?? -1)")
        return result == .success
    }

    /// Some AppKit and SwiftUI nodes answer the informal AX selectors without the protocol.
    private static func accessibilityTexts(_ element: Any, depth: Int, into texts: inout [String]) {
        guard depth < 60, let node = element as? NSObject else { return }
        func ask(_ name: String) -> Any? {
            let selector = NSSelectorFromString(name)
            return node.responds(to: selector) ? node.perform(selector)?.takeUnretainedValue() : nil
        }
        for name in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"] {
            if let text = ask(name) as? String, !text.isEmpty { texts.append(text) }
        }
        for child in ask("accessibilityChildren") as? [Any] ?? [] {
            accessibilityTexts(child, depth: depth + 1, into: &texts)
        }
    }

}
#endif
