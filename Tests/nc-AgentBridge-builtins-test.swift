// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Service/AgentActionIndex.swift
// notchcast-sources: Tinycast/Features/AgentBridge/UI/AgentBuiltInActions.swift
// notchcast-sources: Tinycast/Features/HotKeys/Model/HotKeyAction.swift
// notchcast-sources: Tinycast/Features/Launcher/Model/CommandID.swift
// notchcast-sources: Tinycast/Features/QuickActions/Model/BuiltInQuickAction.swift
// notchcast-sources: Tinycast/Features/Quicklinks/Model/Quicklink.swift
// notchcast-sources: Tinycast/Features/Quicklinks/Model/QuicklinkDestination.swift
// notchcast-sources: Tinycast/Features/SystemActions/Model/SystemAction.swift
// notchcast-sources: Tinycast/Features/WindowManagement/Model/WindowCommand.swift
// notchcast-sources: Tinycast/Features/DeepLinks/Model/DeepLinkInput.swift
// notchcast-sources: Tinycast/Features/DeepLinks/Model/DeepLinkConsentPolicy.swift
// notchcast-sources: Tinycast/Platform/LocalizedResource.swift
import Foundation

struct StoredSnippet { typealias ID = String }

@MainActor
enum NotchcastCommandCatalog {
    struct Command {
        struct Entry { let id: String }
        let entry: Entry
        let name: String
    }
    static let all = [Command(entry: .init(id: "command:toggle-island"), name: "Toggle Island"),
                      Command(entry: .init(id: "command:nc-test"), name: "Test Command")]
    static var preference = true
    static var condition = true
    static func isEnabled(_ id: String) -> Bool { preference && condition }
}

@MainActor
final class AppCore {
    final class HotKeyFixture {
        var actions: [HotKeyAction] = []
        func perform(_ action: HotKeyAction) { actions.append(action) }
    }

    final class VolumeFixture {
        var levels: [Double] = []
        func setVolume(_ level: Double) { levels.append(level) }
    }

    let hotKeys = HotKeyFixture()
    let systemActionCoordinator = VolumeFixture()
    var hidden: Set<HotKeyAction> = []

    func allowsHotKeyAction(_ action: HotKeyAction) -> Bool {
        if case .notchcastCommand(let id) = action { return NotchcastCommandCatalog.isEnabled(id) }
        return !hidden.contains(action)
    }
}

@main
@MainActor
struct AgentBuiltInTests {
    static func check(_ value: Bool, _ message: String = "check failed") { precondition(value, message) }

    static func main() async throws {
        let core = AppCore()
        let index = AgentActionIndex()
        try AgentBuiltInActions.register(in: index, core: core)
        index.start()
        check(index.actionIDs.contains("command:toggle-island"), "fork launcher command missing")
        for id in ["notchcast.launcher", "notchcast.dictation", "system-action:set-volume", "window-command:left-half"] {
            check(index.actionIDs.contains(id), "\(id) missing")
        }
        let fork = AgentRequest(verb: .run, id: "command:toggle-island")
        check((await index.handle(fork)).code == .ok)
        check(core.hotKeys.actions.removeLast() == .notchcastCommand(entryID: "command:toggle-island"))
        for enabled in [false, true] {
            NotchcastCommandCatalog.preference = enabled
            let reply = await index.handle(.init(verb: .list))
            guard case .object(let fields) = reply.result, case .array(let actions) = fields["actions"],
                  let action = actions.first(where: {
                      guard case .object(let fields) = $0 else { return false }
                      return fields["id"] == .string("command:toggle-island")
                  }), case .object(let descriptor) = action else { preconditionFailure("missing fork action") }
            check(descriptor["available"] == .bool(enabled))
            check(descriptor["danger"] == .string("harmless"))
            check((await index.handle(.init(verb: .run, id: fork.id, dryRun: true))).code == (enabled ? .ok : .failed))
        }
        NotchcastCommandCatalog.condition = false
        check((await index.handle(fork)).code == .failed)
        check((await index.handle(.init(verb: .run, id: fork.id, dryRun: true))).code == .failed)
        NotchcastCommandCatalog.condition = true
        check((await index.handle(.init(verb: .run, id: "command:nc-test"))).code == .declined)
        check(core.hotKeys.actions.isEmpty)
        print("PASS: fork registration, live preference/condition, unavailable dry-run, consent and hotkey dispatch")
        check(!index.actionIDs.contains(CommandID.runShellCommand.rawValue))
        check(!index.actionIDs.contains(CommandID.quit.rawValue))
        check(!index.actionIDs.contains { $0.hasPrefix("quicklink:") || $0.hasPrefix("extension:") })
        let settings = AgentRequest(verb: .run, id: CommandID.settings.rawValue)
        check(await index.handle(settings) == .init(code: .ok, result: .object(["status": .string("dispatched")])))
        check(core.hotKeys.actions == [.command(.settings)])
        core.hidden.insert(.command(.settings))
        check(await index.handle(settings) == .init(code: .failed))
        check(core.hotKeys.actions.count == 1)

        let volume = AgentRequest(verb: .run, id: "system-action:set-volume",
                                  parameters: .object(["level": .number(0.75)]))
        check(await index.handle(volume) == .init(code: .declined))
        check(core.systemActionCoordinator.levels.isEmpty)
        let dangerous = AgentRequest(verb: .run, id: "system-action:empty-trash", dryRun: true)
        let preview = await index.handle(dangerous)
        guard case .object(let fields) = preview.result else { preconditionFailure("missing preview") }
        check(fields["danger"] == .string("dangerous"))
        index.authorize = { _, _ in {} }
        check((await index.handle(volume)).code == .ok)
        check(core.systemActionCoordinator.levels == [0.75])
        let window = AgentRequest(verb: .run, id: "window-command:left-half")
        check((await index.handle(window)).code == .ok)
        check(core.hotKeys.actions.last == .windowCommand(id: .leftHalf))
        print("PASS: real upstream catalogues, hidden-action gate, danger classification and injected dispatch including volume")
    }
}
