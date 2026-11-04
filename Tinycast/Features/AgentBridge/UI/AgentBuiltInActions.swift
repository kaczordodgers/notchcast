import Foundation

@MainActor
enum AgentBuiltInActions {
    static func register(in index: AgentActionIndex, core: AppCore) throws {
        for action in HotKeyAction.builtInActions {
            let id: String
            let title: String
            switch action {
            case .togglePalette:
                id = "notchcast.launcher"
                title = String(localized: "App Launcher")
            case .dictation:
                id = "notchcast.dictation"
                title = String(localized: "Dictation")
            case .command(let command):
                id = command.rawValue
                title = command.name
            default: continue
            }
            try register(action, id: id, title: title, index: index, core: core)
        }
        for action in SystemActionCatalog.all {
            let danger: AgentAction.Danger
            switch action.confirmation {
            case .none: danger = .consent
            case .computed, .required, .followsFinder: danger = .dangerous
            }
            try register(.systemAction(id: action.id), id: action.entryID, title: action.name,
                         danger: danger, index: index, core: core)
        }
        for command in WindowCommandCatalog.all {
            try register(.windowCommand(id: command.id), id: command.entryID, title: command.name,
                         index: index, core: core)
        }
    }

    private static func register(
        _ action: HotKeyAction, id: String, title: String, danger: AgentAction.Danger? = nil,
        index: AgentActionIndex, core: AppCore
    ) throws {
        var descriptor = AgentAction(id: id, title: title,
                                     danger: danger ?? (DeepLinkConsentPolicy.requiresConsent(action) ? .consent : .harmless))
        if action == .systemAction(id: .setVolume) {
            descriptor.parameters = .init(properties: ["level": .init(kind: .number, minimum: 0, maximum: 1)],
                                          required: ["level"])
        }
        try index.register(.init(action: descriptor, isAvailable: { [weak core] in
            core?.allowsHotKeyAction(action) == true
        }, run: { [weak core] parameters in
            try Task.checkCancellation()
            guard let core, core.allowsHotKeyAction(action) else { throw AgentReply.Code.failed }
            if action == .systemAction(id: .setVolume),
               case .object(let fields) = parameters, case .number(let level)? = fields["level"] {
                core.systemActionCoordinator.setVolume(level)
            } else {
                core.hotKeys.perform(action)
            }
            return .object(["status": .string("dispatched")])
        }))
    }
}
