import ApplicationServices
import Foundation

/// The one owner of the add-on system: created by AppCore in `start`, stopped at terminate.
@MainActor
final class NotchcastCore {
    let controller: NotchcastController
    let dictationServer: DictationServer
    private var trustMonitor: NotchcastTrustMonitor?
    private var launcherHides: NotchcastLauncherHides?
    private var globeTrigger: NotchcastGlobeTrigger?
    private let dictationIsland = DictationIslandCoordinator()

    init(core: AppCore, addons: [any NotchcastAddon.Type] = NotchcastRegistry.addons) {
        let bundleID = Bundle.main.bundleIdentifier ?? "Notchcast"
        let defaults = UserDefaults(suiteName: NotchcastPreferences.suiteName(bundleID: bundleID)) ?? .standard
        let hub = NotchcastTapHub(
            syntheticTag: Paster.tinycastEventTag, isTrusted: { AXIsProcessTrusted() },
            makeSession: NotchcastTapThread.start)
        controller = NotchcastController(
            addons: addons, defaults: defaults, hub: hub, dictation: NotchcastDictationBridge(core: core),
            services: NotchcastServices(core: core), presenter: core.islandPresenter)
        dictationServer = DictationServer(
            defaults: defaults, settings: core.settings, coordinator: core.dictationCoordinator,
            runner: controller.transcription)
        NotchcastPane.install(Set(controller.switches.map(\.category)))
        for context in controller.slots.flatMap({ [$0.context, $0.recovery] }) {
            context.confirm = { [weak core] title, message, confirmTitle in
                await core?.confirm(title: title, message: message, symbol: nil, confirmTitle: confirmTitle,
                                    tone: .neutral, confirmRole: .standard) ?? false
            }
            context.confirmDestructive = { [weak core] title, message, confirmTitle in
                await core?.confirm(title: title, message: message, symbol: nil, confirmTitle: confirmTitle) ?? false
            }
        }
        controller.wireAskSecret { [weak core] requester, title, message, fieldTitle, confirmTitle in
            await core?.askSecret(
                requester: requester, title: title, message: message, fieldTitle: fieldTitle, confirmTitle: confirmTitle)
        }
        let commands = addons.flatMap { $0.commands }
        NotchcastSettingsSearch.install(
            controller.switches,
            commandWords: Dictionary(grouping: commands, by: \.switchID)
                .mapValues { $0.flatMap { [$0.name] + $0.keywords } })
        let launcher = core.launcherCoordinator
        let tabs = Dictionary(
            controller.switches.map { ($0.id, NotchcastPane.holding($0.category)) },
            uniquingKeysWith: { first, _ in first })
        controller.onCommandsChanged = { [weak self, weak core, weak controller] commands in
            self?.launcherHides?.include(Set(commands.map(\.id)))
            core?.appIndex.extraCommandEntries = (controller?.launcherCommands(commands) ?? []).map {
                AppEntry(notchcastCommand: $0.id, name: $0.name, symbol: $0.symbol, keywords: $0.keywords,
                         owner: .notchcast(tabs[$0.switchID] ?? .island))
            }
            core?.hotKeys.extraActions = commands.map { .notchcastCommand(entryID: $0.id) }
        }
        core.hotKeys.onRunNotchcastCommand = { [weak controller] entryID in
            _ = controller?.run(entryID: entryID)
        }
        launcher.runExtraCommand = { [weak controller, weak core] entryID in
            guard let controller, let core, controller.enabledCommands.contains(where: { $0.id == entryID })
            else { return false }
            // Read before the hide, which clears the palette's typed arguments.
            let argument = NotchcastArgumentAccessory.value(for: entryID, vm: core.palette)
            core.paletteCoordinator.hidePalette(restoreFocus: true)
            return controller.submit(entryID: entryID, argument: argument)
        }
        LauncherScreen.extraAccessory = { [weak controller, weak core] entry, focus, onSubmit in
            guard let core, let title = controller?.enabledCommands.first(where: { $0.id == entry.id })?.argument?.title
            else { return nil }
            return NotchcastArgumentAccessory.make(
                entry: entry, title: title, vm: core.palette, metrics: core.settings.interfaceSize.metrics,
                focus: focus, onSubmit: onSubmit)
        }
        let stockLauncherShown = core.paletteCoordinator.onLauncherShown
        core.paletteCoordinator.onLauncherShown = { [weak controller] in
            stockLauncherShown?()
            controller?.launcherShown()
        }
        launcherHides = NotchcastLauncherHides(
            visibility: core.visibility, preferences: controller.preferences, commandIDs: Set(commands.map(\.id)))
        trustMonitor = NotchcastTrustMonitor(hub: hub)
        globeTrigger = NotchcastGlobeTrigger(core: core, hub: hub)
        let typingDisplay = TypingDisplayReader()
        dictationIsland.start(core: core, captureDisplay: { [weak dictation = core.dictationCoordinator] in
            typingDisplay.capture(dictation?.target)
        }, typingDisplay: typingDisplay.display)
        if let seed = DictationFirstModel.seed(
            stored: UserDefaults.standard.string(forKey: AppSettingsKey.dictationModel.rawValue)),
            let model = DictationModel(rawValue: seed) { core.settings.dictationModel = model }
        controller.start()
        dictationServer.start()
    }

    func stop() {
        dictationServer.stop()
        trustMonitor = nil
        globeTrigger?.stop()
        controller.stop()
        controller.hub.stop()
    }
}
