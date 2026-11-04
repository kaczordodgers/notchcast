// notchcast-sources: -swift-version 6 -strict-concurrency=complete
// notchcast-sources: Tinycast/Features/AgentMCPServer/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentMCPServer/Service/AgentMCPModule*.swift
// notchcast-sources: Tinycast/Features/AgentMCPServer/Service/AgentMCPIndexBackend.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Model/*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Service/AgentActionIndex.swift
// notchcast-sources: Tinycast/Features/AgentBridge/Service/AgentSocket*.swift
// notchcast-sources: Tinycast/Features/AgentBridge/UI/AgentRequest+Audit.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Model/AgentAuditEntry.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Model/AgentConsentPolicy.swift
// notchcast-sources: Tinycast/Features/AgentConsent/Service/AgentAuditStore.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastModule.swift
import Foundation
import Observation

enum NotchcastFeature { case agentMCPServer }

@MainActor @Observable
final class NotchcastPreferences {
    var enabled = false
    func isOn(_ feature: NotchcastFeature) -> Bool { enabled }
}

@main
@MainActor
struct StdioTest {
    static let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"#
        + #""protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"fixture","version":"1"}}}"#
    static let list = #"{"jsonrpc":"2.0","id":"catalog","method":"tools/list"}"#
    static let call = #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"#
        + #""name":"fixture.echo","arguments":{"text":"hello"}}}"#

    static func offPool<Value: Sendable>(_ work: @escaping @Sendable () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                do { continuation.resume(returning: try work()) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    static func transcript(_ lines: [String], folder: URL, socket: URL) async throws -> [[String: AgentJSON]] {
        try await offPool {
            let source = folder.appending(path: "input-\(UUID())")
            let destination = folder.appending(path: "output-\(UUID())")
            try Data(lines.joined(separator: "\n").utf8).write(to: source)
            try Data().write(to: destination)
            let input = try FileHandle(forReadingFrom: source)
            let output = try FileHandle(forWritingTo: destination)
            defer { try? input.close(); try? output.close() }
            try AgentMCPStdio.run(input: input, output: output) { AgentSocketClient.send($0, to: socket) }
            return try Data(contentsOf: destination).split(separator: 10).map {
                guard case .object(let fields) = try JSONDecoder().decode(AgentJSON.self, from: Data($0)) else {
                    preconditionFailure("stdout contained a non-JSON-RPC line")
                }
                precondition(fields["jsonrpc"] == .string("2.0"))
                return fields
            }
        }
    }

    static func error(_ reply: [String: AgentJSON], code: Double) -> Bool {
        guard case .object(let fields) = reply["error"] else { return false }
        return fields["code"] == .number(code)
    }

    static func main() async throws {
        let parsed = try AgentRequest.parse(["mcp"])
        precondition(parsed.request.verb == .mcp)
        do { _ = try AgentRequest.parse(["mcp", "extra"]); preconditionFailure() } catch {}
        do { _ = try AgentRequest.parse(["mcp", "--dry-run"]); preconditionFailure() } catch {}
        let folder = URL(filePath: "/tmp/nc-mcp-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let socket = folder.appending(path: "private/socket")
        let index = AgentActionIndex()
        var available = true
        var authorized = false
        var executions = 0
        var approvals = 0
        var audit: [(AgentRequest, AgentReply)] = []
        let auditStore = AgentAuditStore(directory: folder.appending(path: "audit"))
        try index.register(.init(action: .init(id: "fixture.echo", title: "Echo",
            parameters: .init(properties: ["text": .init(kind: .string)], required: ["text"]), danger: .consent),
            isAvailable: { available }, run: { value in executions += 1; return value }))
        try index.register(.init(action: .init(id: "fixture.safe", title: "Safe", danger: .harmless),
                                 run: { _ in .string("safe") }))
        try index.register(.init(id: "fixture.state", title: "State", read: { .bool(true) }))
        index.authorize = { _, _ in approvals += 1; return authorized }
        index.didComplete = { request, reply in
            if request.verb == .run { audit.append((request, reply)) }
            if let entry = request.auditEntry(reply: reply, time: Date()) {
                do { try await auditStore.append(entry) } catch { precondition(Task.isCancelled) }
            }
        }
        index.start()
        let module = AgentMCPModule()
        module.configure(index: index)
        let preferences = NotchcastPreferences()
        let controller = NotchcastModuleController([
            .init(requires: [.agentMCPServer], module: module)
        ], preferences: preferences)
        controller.run()
        let server = AgentSocketServer(socketURL: socket) { await index.handle($0) }
        try server.start()
        defer { server.stop(); module.stop(); index.stop() }
        let disabled = try await transcript([initialize, call], folder: folder, socket: socket)
        precondition(disabled.count == 2 && disabled.allSatisfy { error($0, code: -32000) })
        precondition(disabled[1]["id"] == .number(3) && executions == 0 && approvals == 0)
        print("PASS switch off returns JSON-RPC Server stopped over the fake app socket")

        preferences.enabled = true
        for _ in 0..<20 { await Task.yield() }
        precondition(module.engine.isRunning)
        authorized = true
        let roundTrip = try await transcript([
            initialize, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#, list, call,
            #"{"jsonrpc":"2.0","id":4,"method":"resources/list"}"#,
            #"{"jsonrpc":"2.0","id":5,"method":"resources/read","params":{"uri":"notchcast-state:fixture.state"}}"#
        ], folder: folder, socket: socket)
        precondition(roundTrip.count == 5 && roundTrip.allSatisfy { $0["error"] == nil })
        precondition(roundTrip[1]["id"] == .string("catalog"))
        guard case .object(let catalog) = roundTrip[1]["result"], case .array(let tools) = catalog["tools"] else {
            preconditionFailure("missing tools")
        }
        precondition(tools.count == 2)
        guard case .object(let tool) = tools[0], case .object(let schema) = tool["inputSchema"] else {
            preconditionFailure("missing schema")
        }
        precondition(tool["name"] == .string("fixture.echo") && schema["required"] == .array([.string("text")]))
        precondition(executions == 1 && approvals == 1 && audit.count == 1 && audit[0].1.code == .ok)
        precondition(audit[0].0.isMCP)
        _ = await index.handle(.init(verb: .run, id: "fixture.safe"))
        precondition(audit.last?.0.isMCP == false)
        let entries = try await auditStore.entries()
        precondition(entries.map(\.surface) == [.mcp, .cli])
        audit.removeLast()
        approvals -= 1
        print("PASS nested MCP run carries MCP audit provenance; CLI run retains CLI provenance")
        let encoded = String(bytes: try JSONEncoder().encode(roundTrip[2]), encoding: .utf8)!
        precondition(encoded.contains("hello") && encoded.contains("content"))
        print("PASS initialize -> tools/list -> tools/call -> stdout; registered schema, resources, consent and audit")

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let streaming = Task {
            try await offPool {
                try AgentMCPStdio.run(input: inputPipe.fileHandleForReading,
                                     output: outputPipe.fileHandleForWriting) { AgentSocketClient.send($0, to: socket) }
            }
        }
        try inputPipe.fileHandleForWriting.write(contentsOf: Data((initialize + "\n").utf8))
        let liveReply = try await offPool {
            try AgentSocketIO.readLine(outputPipe.fileHandleForReading.fileDescriptor, timeout: .seconds(2))
        }
        precondition(String(bytes: liveReply, encoding: .utf8)!.contains("serverInfo"))
        try await offPool {
            for _ in 0..<17 {
                try inputPipe.fileHandleForWriting.write(contentsOf: Data(repeating: 120, count: 8192))
            }
        }
        let longReply = try await offPool {
            try AgentSocketIO.readLine(outputPipe.fileHandleForReading.fileDescriptor, timeout: .seconds(2))
        }
        precondition(String(bytes: longReply, encoding: .utf8)!.contains("badRequest"))
        try inputPipe.fileHandleForWriting.write(contentsOf: Data(("\n" + list + "\n").utf8))
        let recovered = try await offPool {
            try AgentSocketIO.readLine(outputPipe.fileHandleForReading.fileDescriptor, timeout: .seconds(2))
        }
        precondition(String(bytes: recovered, encoding: .utf8)!.contains("tools"))
        try inputPipe.fileHandleForWriting.close()
        try await streaming.value
        try inputPipe.fileHandleForReading.close()
        try outputPipe.fileHandleForWriting.close()
        try outputPipe.fileHandleForReading.close()
        print("PASS interactive initialize replies before stdin closes")
        print("PASS chunk-spanning oversized pipe line is discarded and initialized session survives")

        let oversized = try await transcript([String(repeating: "x", count: AgentMCPStdio.lineLimit + 1),
                                               initialize, list], folder: folder, socket: socket)
        precondition(oversized.count == 3 && error(oversized[0], code: -32000))
        precondition(oversized[1]["error"] == nil && oversized[2]["error"] == nil)
        print("PASS oversized line emits one JSON-RPC error and following lines remain usable")

        let persistentID = UUID().uuidString
        let initializationLine = initialize
        try await offPool {
            let client = AgentSocketClient.Session()
            precondition(client.send(.init(verb: .mcp, id: persistentID, parameters: .string(initializationLine)),
                                     to: socket).code == .ok)
        }
        var removed = false
        for _ in 0..<200 {
            let response = await module.engine.receive(line: Data(list.utf8), session: persistentID)!
            if String(bytes: response, encoding: .utf8)!.contains("Initialize first") { removed = true; break }
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(removed)
        print("PASS real persistent socket close removes MCP session on app side")

        authorized = false
        let refused = try await transcript([initialize, call], folder: folder, socket: socket)
        precondition(error(refused[1], code: -32001) && executions == 1 && approvals == 2)
        precondition(audit.count == 2 && audit[1].1.code == .declined)
        precondition(audit[1].0.parameters == .object(["text": .string("hello")]))
        print("PASS consent refusal is JSON-RPC -32001, audited as declined, with no execution")

        let isolated = try await transcript([list], folder: folder, socket: socket)
        precondition(error(isolated[0], code: -32002))
        available = false
        let unavailable = try await transcript([initialize, list, call], folder: folder, socket: socket)
        guard case .object(let filtered) = unavailable[1]["result"],
              case .array(let filteredTools) = filtered["tools"] else { preconditionFailure() }
        precondition(filteredTools.count == 1 && error(unavailable[2], code: -32602))
        precondition(approvals == 2 && audit.count == 2)
        available = true
        let invalid = try await transcript([initialize,
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"fixture.echo","arguments":{}}}"#,
            #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"unregistered"}}"#,
            "not-json"
        ], folder: folder, socket: socket)
        precondition(error(invalid[1], code: -32602) && error(invalid[2], code: -32602))
        precondition(error(invalid[3], code: -32700) && executions == 1 && approvals == 2)
        print("PASS per-client initialization, availability filtering, invalid arguments, unknown tools and parse errors")

        index.authorize = { action, _ in
            let decision = AgentConsentPolicy.decide(agentID: "fixture", actionID: action.id,
                danger: action.danger == .dangerous ? .dangerous : .consent, grants: [], now: Date())
            return decision == .allow
        }
        try index.register(.init(action: .init(id: "fixture.dangerous", title: "Dangerous", danger: .dangerous),
                                 run: { _ in preconditionFailure("dangerous action executed") }))
        let policyRefused = try await transcript([initialize, call,
            #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"fixture.dangerous"}}"#
        ], folder: folder, socket: socket)
        precondition(error(policyRefused[1], code: -32001) && error(policyRefused[2], code: -32001))
        precondition(executions == 1)
        print("PASS real consent policy refuses dangerous actions and declines consent without a grant")
        let auditBeforeCancellation = audit.count
        var waiting = false
        index.authorize = { _, _ in
            waiting = true
            do { try await Task.sleep(for: .seconds(10)) } catch {}
            return true
        }
        let pending = Task { try await transcript([initialize, call], folder: folder, socket: socket) }
        while !waiting { await Task.yield() }
        preferences.enabled = false
        for _ in 0..<20 { await Task.yield() }
        let cancelled = try await pending.value
        precondition(cancelled[1]["error"] != nil && executions == 1)
        precondition(audit.count == auditBeforeCancellation + 1 && audit.last?.1.code != .ok)
        precondition(!module.engine.isRunning)
        preferences.enabled = true
        for _ in 0..<20 { await Task.yield() }
        let restarted = try await transcript([list], folder: folder, socket: socket)
        precondition(error(restarted[0], code: -32002))
        print("PASS disabling during consent cancels execution and restarting requires initialization")

        server.stop()
        let disconnected = try await transcript([initialize,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
        ], folder: folder, socket: socket)
        precondition(disconnected.count == 1 && error(disconnected[0], code: -32000))
        precondition(disconnected[0]["id"] == .number(1))
        print("PASS missing app socket returns JSON-RPC error and notifications emit no stdout")
    }
}
