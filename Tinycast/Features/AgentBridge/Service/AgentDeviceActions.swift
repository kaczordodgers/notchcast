import Foundation

@MainActor
enum AgentDeviceActions {
    enum Device: String, CaseIterable {
        case treadmill, katana

        var operations: [String] {
            switch self {
            case .treadmill: ["start", "stop", "pause", "resume", "speed"]
            case .katana: ["channel", "tone"]
            }
        }
    }

    static func register(_ device: Device, backend: any AgentDeviceBackend,
                         in index: AgentActionIndex) throws {
        let prefix = "device.\(device.rawValue)"
        try index.register(.init(id: prefix, title: prefix, isAvailable: { backend.isAvailable }, read: {
            try await backend.readState()
        }))
        for operation in device.operations {
            let id = "\(prefix).\(operation)"
            let action = AgentAction(id: id, title: id, parameters: schema(device, operation), danger: .dangerous)
            try index.register(.init(action: action, isAvailable: { backend.isAvailable }, run: { parameters in
                try Task.checkCancellation()
                guard backend.isAvailable else { throw AgentReply.Code.failed }
                return try await backend.perform(operation, parameters: parameters)
            }))
        }
    }

    private static func schema(_ device: Device, _ operation: String) -> AgentParameterSchema {
        switch (device, operation) {
        case (.treadmill, "start"):
            .init(properties: ["speed": .init(kind: .number, minimum: 1, maximum: 6),
                               "minutes": .init(kind: .integer, minimum: 0, maximum: 1092)],
                  required: ["speed", "minutes"])
        case (.treadmill, "speed"):
            .init(properties: ["speed": .init(kind: .number, minimum: 1, maximum: 6)], required: ["speed"])
        case (.katana, "channel"):
            .init(properties: ["channel": .init(kind: .integer,
                allowedValues: [0, 1, 2, 5, 6].map { .number(Double($0)) })], required: ["channel"])
        case (.katana, "tone"):
            .init(properties: ["toneID": .init(kind: .string, minimumLength: 1),
                               "channel": .init(kind: .integer,
                                allowedValues: [0, 1, 2, 5, 6].map { .number(Double($0)) })],
                  required: ["toneID", "channel"])
        default: .init()
        }
    }
}
