// notchcast-sources: Tinycast/Features/CommandRunner/Model/*.swift
// notchcast-sources: Tinycast/Features/CommandRunner/Service/CatalogShellCommandRunner.swift
// notchcast-sources: Tinycast/Features/CommandRunner/Service/CommandQuickAdd.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/NotchcastFeature+SettingsGroup.swift
import Foundation
import Synchronization

@main
struct CommandCatalogTest {
    static func main() async throws {
        let payload = "spaces 'quotes' \"double\"; $(touch /tmp/never-run)\nexit 9"
        let entry = HostCommandCatalog.Entry(
            id: "test", title: "Title " + payload, executable: "/synthetic/tool",
            arguments: ["fixed argument", "'quoted'"], hosts: ["host-a"])
        let catalog = try HostCommandCatalog(base: [entry], host: "host-a")
        precondition(catalog.entries == [entry])
        let filtered = try HostCommandCatalog(base: [entry], host: "host-b")
        precondition(filtered.entries.isEmpty)
        let override = HostCommandCatalog.Entry(id: "test", title: "Override", executable: "/other")
        let overridden = try HostCommandCatalog(base: [entry], overrides: [override], host: "host-b")
        precondition(overridden.entries == [override])
        do {
            _ = try HostCommandCatalog(base: [entry, entry], host: "host-a")
            preconditionFailure("duplicate accepted")
        } catch {}
        let requests = Mutex<[CatalogShellCommandRunner.Request]>([])
        let runner = CatalogShellCommandRunner { request in
            requests.withLock { $0.append(request) }
            return .init(exitStatus: 7, standardOutput: Data("out".utf8), standardError: Data("err".utf8))
        }
        let result = try await runner.run(entry, arguments: [payload])
        precondition(!result.succeeded && result.exitStatus == 7)
        precondition(result.standardOutput == Data("out".utf8) && result.standardError == Data("err".utf8))
        let request = requests.withLock { $0[0] }
        precondition(request.executable == "/synthetic/tool")
        precondition(request.arguments == ["fixed argument", "'quoted'", payload])
        precondition(!request.arguments.contains("-c") && !request.arguments.contains(entry.title))
        let started = Mutex(false)
        let cancelledRunner = CatalogShellCommandRunner { _ in
            started.withLock { $0 = true }
            try await Task.sleep(for: .seconds(60))
            return .init(exitStatus: 0, standardOutput: Data(), standardError: Data())
        }
        let task = Task { try await cancelledRunner.run(entry) }
        while !started.withLock({ $0 }) { await Task.yield() }
        task.cancel()
        do { _ = try await task.value; preconditionFailure("cancel ignored") } catch is CancellationError {}
        let item = CommandListItem(id: "item", title: "Item", target: .command(id: entry.id, arguments: [payload]))
        let decoded = try JSONDecoder().decode(CommandListItem.self, from: JSONEncoder().encode(item))
        precondition(decoded == item)
        let token = "synthetic-secret"
        let reads = Mutex(0)
        let quick = CommandQuickAdd(readToken: {
            reads.withLock { $0 += 1 }; return token
        }, client: { text, secret in
            precondition(text == "task text" && secret == token); return true
        })
        try await quick.add("  task text  ")
        try await quick.add("task text")
        precondition(reads.withLock { $0 } == 2)
        struct SecretError: Error { let value: String }
        let failed = CommandQuickAdd(readToken: { token }, client: { _, _ in throw SecretError(value: token) })
        do { try await failed.add("task"); preconditionFailure("error ignored") } catch {
            precondition(!String(reflecting: error).contains(token))
        }
        let rejected = CommandQuickAdd(readToken: { token }, client: { _, _ in false })
        do { try await rejected.add("task"); preconditionFailure("failure ignored") } catch {
            precondition(error == .failed)
        }
        let missing = CommandQuickAdd(readToken: { nil }, client: { _, _ in preconditionFailure("client called") })
        do { try await missing.add("task"); preconditionFailure("missing token accepted") } catch {
            precondition(error == .missingToken)
        }
        precondition(!NotchcastFeature.commandRunner.defaultEnabled)
        precondition(!NotchcastFeature.commandRunner.needsIsland)
        precondition(NotchcastFeature.commandRunner.settingsGroup == .launcher)
        print("command catalogue: passed (synthetic fixtures only)")
    }
}
