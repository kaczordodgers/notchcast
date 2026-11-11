import Foundation

/// The `list` reply. Its key names are written here and nowhere else.
struct AgentCatalog: Equatable, Sendable {
    struct Action: Equatable, Sendable {
        let id: String
        let title: String
        let parameters: AgentJSON
        let danger: AgentAction.Danger
        let available: Bool

        var json: AgentJSON {
            .object([
                "id": .string(id), "title": .string(title), "parameters": parameters,
                "danger": .string(danger.rawValue), "available": .bool(available)
            ])
        }

        init(id: String, title: String, parameters: AgentJSON, danger: AgentAction.Danger, available: Bool) {
            (self.id, self.title, self.parameters, self.danger, self.available) = (id, title, parameters, danger, available)
        }

        init?(_ json: AgentJSON) {
            guard case .object(let fields) = json, case .string(let id) = fields["id"],
                  case .string(let title) = fields["title"], let parameters = fields["parameters"],
                  case .string(let text) = fields["danger"], let danger = AgentAction.Danger(rawValue: text),
                  case .bool(let available) = fields["available"] else { return nil }
            self.init(id: id, title: title, parameters: parameters, danger: danger, available: available)
        }
    }

    struct State: Equatable, Sendable {
        let id: String
        let title: String
        let available: Bool

        var json: AgentJSON {
            .object(["id": .string(id), "title": .string(title), "available": .bool(available)])
        }

        init(id: String, title: String, available: Bool) {
            (self.id, self.title, self.available) = (id, title, available)
        }

        init?(_ json: AgentJSON) {
            guard case .object(let fields) = json, case .string(let id) = fields["id"],
                  case .string(let title) = fields["title"],
                  case .bool(let available) = fields["available"] else { return nil }
            self.init(id: id, title: title, available: available)
        }
    }

    var actions: [Action]
    var states: [State]

    var json: AgentJSON {
        .object(["actions": .array(actions.map(\.json)), "states": .array(states.map(\.json))])
    }

    init(actions: [Action], states: [State]) {
        (self.actions, self.states) = (actions, states)
    }

    init?(_ json: AgentJSON) {
        guard case .object(let fields) = json, case .array(let actions) = fields["actions"],
              case .array(let states) = fields["states"] else { return nil }
        self.init(actions: actions.compactMap(Action.init), states: states.compactMap(State.init))
    }
}
