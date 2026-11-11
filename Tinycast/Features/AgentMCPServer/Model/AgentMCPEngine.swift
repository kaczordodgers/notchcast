import Foundation

@MainActor
final class AgentMCPEngine {
    private var backend: (any AgentMCPBackend)?
    private(set) var isRunning = false
    private var initialized: [String] = []
    private var generation = UUID()
    private var pending: [UUID: (session: String, task: Task<Data, any Error>)] = [:]

    func configure(backend: any AgentMCPBackend) {
        stop()
        self.backend = backend
    }

    func start() { isRunning = true }

    func stop() {
        isRunning = false
        initialized.removeAll()
        generation = UUID()
        for operation in pending.values { operation.task.cancel() }
    }

    func endSession(_ session: String) {
        initialized.removeAll { $0 == session }
        for operation in pending.values where operation.session == session { operation.task.cancel() }
    }

    func receive(line: Data, session: String) async -> Data? {
        let value: Any
        do {
            value = try JSONSerialization.jsonObject(with: line, options: .fragmentsAllowed)
        } catch { return response(id: NSNull(), error: -32700, message: "Parse error") }
        guard let request = value as? [String: Any], request["jsonrpc"] as? String == "2.0",
              let method = request["method"] as? String,
              request["id"] == nil || request["id"] is String || request["id"] is NSNull
                || ((request["id"] as? NSNumber).map {
                    String(cString: $0.objCType) != "c" && $0.doubleValue.isFinite
                } ?? false) else {
            return response(id: NSNull(), error: -32600, message: "Invalid request")
        }
        let id = request["id"] ?? NSNull()
        if let params = request["params"], !(params is [String: Any]) && !(params is [Any]) {
            return request["id"] == nil ? nil : response(id: id, error: -32602, message: "Invalid params")
        }
        guard request["id"] != nil else { return nil }
        guard isRunning else { return response(id: id, error: -32000, message: "Server stopped") }
        if initialized.contains(session) {
            initialized.removeAll { $0 == session }
            initialized.append(session)
        }
        let operation = generation
        let params = request["params"] as? [String: Any] ?? [:]
        do {
            guard let backend else {
                return response(id: id, error: -32000, message: "MCP backend unavailable")
            }
            let result: [String: Any]
            switch method {
            case "initialize":
                guard params["protocolVersion"] is String, params["capabilities"] is [String: Any],
                      params["clientInfo"] is [String: Any] else {
                    return response(id: id, error: -32602, message: "Invalid params")
                }
                if !initialized.contains(session) {
                    if initialized.count == 64 { endSession(initialized[0]) }
                    initialized.append(session)
                }
                result = ["protocolVersion": "2025-06-18", "capabilities": ["tools": [:], "resources": [:]],
                          "serverInfo": ["name": "notchcast", "version": "1"]]
            case "ping": result = [:]
            default:
                guard initialized.contains(session) else {
                    return response(id: id, error: -32002, message: "Initialize first")
                }
                switch method {
                case "tools/list":
                    result = ["tools": try await backend.actions().map { action in
                        ["name": action.id, "description": "\(action.title) (danger: \(action.danger))",
                         "inputSchema": try JSONSerialization.jsonObject(with: action.inputSchema),
                         "annotations": ["destructiveHint": action.isDestructive,
                                         "openWorldHint": true]] as [String: Any]
                    }]
                case "tools/call":
                    guard let name = params["name"] as? String else {
                        return response(id: id, error: -32602, message: "Invalid tool name")
                    }
                    guard let arguments = (params["arguments"] ?? [:]) as? [String: Any],
                          JSONSerialization.isValidJSONObject(arguments) else {
                        return response(id: id, error: -32602, message: "Invalid arguments")
                    }
                    let actions = try await backend.actions()
                    try validate(operation)
                    guard actions.contains(where: { $0.id == name }) else {
                        return response(id: id, error: -32602, message: "Unknown tool")
                    }
                    let data = try JSONSerialization.data(withJSONObject: arguments)
                    let output = try await perform(session: session) { try await backend.call(name, arguments: data) }
                    result = ["content": [["type": "text", "text": String(bytes: output, encoding: .utf8) ?? ""]]]
                case "resources/list":
                    result = ["resources": try await backend.states().map {
                        ["uri": "notchcast-state:" + $0.id, "name": $0.title, "mimeType": "application/json"]
                    }]
                case "resources/read":
                    guard let uri = params["uri"] as? String,
                          let state = try await backend.states().first(where: {
                              "notchcast-state:" + $0.id == uri
                          }) else {
                        return response(id: id, error: -32602, message: "Unknown resource")
                    }
                    try validate(operation)
                    let output = try await perform(session: session) { try await backend.readState(state.id) }
                    result = ["contents": [["uri": uri, "mimeType": "application/json",
                                             "text": String(bytes: output, encoding: .utf8) ?? ""]]]
                default: return response(id: id, error: -32601, message: "Method not found")
                }
            }
            try validate(operation)
            return response(id: id, result: result)
        } catch let failure as AgentMCPFailure {
            return response(id: id, error: failure.code, message: failure.message)
        } catch {
            return response(id: id, error: -32603, message: "Operation failed")
        }
    }

    private func perform(session: String, work: @escaping @MainActor () async throws -> Data) async throws -> Data {
        let id = UUID()
        let task = Task { try await work() }
        pending[id] = (session, task)
        defer { pending[id] = nil }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await task.value
        } onCancel: { task.cancel() }
    }

    private func validate(_ operation: UUID) throws {
        try Task.checkCancellation()
        guard isRunning, generation == operation else { throw CancellationError() }
    }

    private func response(id: Any, result: [String: Any] = [:], error: Int? = nil, message: String = "") -> Data? {
        var object: [String: Any] = ["jsonrpc": "2.0", "id": id]
        if let error {
            object["error"] = ["code": error, "message": message]
        } else { object["result"] = result }
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys) else { return nil }
        data.append(0x0A)
        return data
    }

    isolated deinit { for operation in pending.values { operation.task.cancel() } }
}
