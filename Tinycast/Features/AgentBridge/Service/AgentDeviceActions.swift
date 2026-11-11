import Foundation

@MainActor
enum AgentDeviceActions {
    static func register(_ backend: any AgentDeviceBackend, in index: AgentActionIndex) throws {
        let prefix = "device.\(backend.deviceName)"
        try index.register(.init(id: prefix, title: prefix, isAvailable: { backend.isAvailable }, read: {
            try await backend.readState()
        }))
        for (operation, parameters) in backend.operations {
            let id = "\(prefix).\(operation)"
            let action = AgentAction(id: id, title: id, parameters: parameters, danger: .dangerous)
            try index.register(.init(action: action, isAvailable: { backend.isAvailable }, run: { parameters in
                try Task.checkCancellation()
                guard backend.isAvailable else { throw AgentReply.Code.failed }
                return try await backend.perform(operation, parameters: parameters)
            }))
        }
    }

    static func unregister(_ backend: any AgentDeviceBackend, from index: AgentActionIndex) {
        let prefix = "device.\(backend.deviceName)"
        for id in [prefix] + backend.operations.map({ "\(prefix).\($0.name)" }) { index.unregister(id) }
    }
}
