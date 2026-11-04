// notchcast-sources: Tinycast/Features/MacUpdate/Model/*.swift
// notchcast-sources: Tinycast/Features/MacUpdate/Service/*.swift Tinycast/Platform/ProcessExit.swift
import Foundation

@MainActor
final class FakeRunner: MacUpdateProcessRunning {
    var commands: [MacUpdateCommand] = []
    var failure = false
    var blocks = false
    var reaped = false
    var fixture = ""

    func run(_ command: MacUpdateCommand) async throws -> MacUpdateRunner.Result {
        commands.append(command)
        if blocks {
            defer { reaped = true }
            try await Task.sleep(for: .seconds(20))
        }
        return .init(status: failure ? 1 : 0, output: fixture)
    }
}

@main
struct MacUpdateTests {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Updated.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let lock = root.appendingPathComponent("maintenance.lock")
        func service(_ runner: FakeRunner, missing: Bool = false,
                     locked: @escaping () -> Bool = { false }) -> MacUpdateService {
            MacUpdateService(runner: runner, home: root.path, appRoot: root.path,
                             exists: { _ in !missing }, resolve: { $0 }, locked: locked,
                             lockTimeout: .milliseconds(60))
        }
        func collect(_ service: MacUpdateService) async -> [MacUpdateService.Progress] {
            var events: [MacUpdateService.Progress] = []
            for await event in service.run()! { events.append(event) }
            return events
        }
        let ordered = FakeRunner()
        let events = await collect(service(ordered))
        assert(events.filter { $0.state == .running }.map(\.step) == MacUpdateStep.allCases)
        assert(ordered.commands.map(\.arguments) == [["update"], ["upgrade"], ["update"], ["upgrade"]])
        let missing = FakeRunner()
        let skips = await collect(service(missing, missing: true))
        assert(skips.count == 4 && missing.commands.isEmpty)
        assert(skips.allSatisfy { if case .skipped(let reason) = $0.state { return !reason.isEmpty }; return false })
        let failing = FakeRunner()
        failing.failure = true
        let failures = await collect(service(failing))
        assert(failing.commands.count == 1)
        assert(failures.last?.state == .failed(""))
        try Data().write(to: lock)
        let waiting = FakeRunner()
        var probes = 0
        let blocked = service(waiting, locked: {
            probes += 1
            return FileManager.default.fileExists(atPath: lock.path)
        })
        let timeout = await collect(blocked)
        assert(timeout.last?.state == .failed("homebrew-lock-timeout"))
        assert(probes > 1 && waiting.commands.isEmpty)
        assert(FileManager.default.fileExists(atPath: lock.path))
        var checks = 0
        let released = FakeRunner()
        _ = await collect(service(released, locked: { checks += 1; return checks < 2 }))
        assert(released.commands.count == 4 && checks >= 2)
        let cancelling = FakeRunner()
        cancelling.blocks = true
        let active = service(cancelling)
        let stream = active.run()!
        assert(active.run() == nil)
        while cancelling.commands.isEmpty { await Task.yield() }
        await active.stop()
        var cancelled = false
        for await event in stream where event.state == .cancelled { cancelled = true }
        assert(cancelled && cancelling.reaped && cancelling.commands.count == 1)
        let cleanup = FakeRunner()
        cleanup.fixture = """
        ==> Upgrading 2 outdated packages:
        ==> Moving App 'Updated.app' to '\(app.path)'
        ==> Moving App 'Other.app' to '/Applications/Other.app'
        ==> Moving App 'Bad.app' to '\(root.path)/../Bad.app'
        """
        _ = await collect(service(cleanup))
        let cleaned = cleanup.commands.filter { $0.path == "/usr/bin/xattr" }
        assert(cleaned.count == 1)
        assert(cleaned[0].arguments == ["-dr", "com.apple.quarantine", app.path])
        assert(cleaned.allSatisfy { $0.arguments.last!.hasPrefix(root.path + "/") })
        print("PASS order, skips, reference failure stop, lock wait/release/timeout, cancel reap, scoped cleanup")
    }
}
