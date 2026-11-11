// notchcast-sources: Tinycast/Features/AudioPriority/Model/*.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityPreferences.swift
// notchcast-sources: Tinycast/Features/AudioPriority/Service/AudioPriorityStore.swift
// notchcast-kit: core platform
// notchcast-sources: Tinycast/Features/CleaningMode/Model/*.swift
// notchcast-sources: Tinycast/Features/CleaningMode/Service/CleaningModeEngine.swift
// notchcast-sources: Tinycast/Features/CleaningMode/CleaningModeModule.swift
// notchcast-sources: Tinycast/Features/AppUpdates/Model/AppUpdate.swift
// notchcast-sources: Tinycast/Features/AppUpdates/AppUpdatesModule.swift
// notchcast-sources: Tinycast/Features/MacUpdate/Model/*.swift
// notchcast-sources: Tinycast/Features/MacUpdate/Service/*.swift Tinycast/Platform/ExecutableLocator.swift
// notchcast-sources: Tinycast/Features/MacUpdate/MacUpdateModule.swift
import Foundation

@MainActor
final class ToolsFakeRunner: MacUpdateProcessRunning {
    var calls = 0
    var blocks = false
    var reaped = false
    func run(_ command: MacUpdateCommand) async throws -> MacUpdateRunner.Result {
        calls += 1
        if blocks {
            do { try await Task.sleep(for: .seconds(20)) } catch {
                await Task.detached { try? await Task.sleep(for: .milliseconds(350)) }.value
                reaped = true
                throw error
            }
        }
        return .init(status: 0, output: "")
    }
}

@main
struct ToolsWiringTests {
    @MainActor
    static func main() async throws {
        let suite = "tools-tests-" + UUID().uuidString
        let prefs = NotchcastPreferences(suiteName: suite)
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        for feature in [NotchcastFeature.cleaningMode, .appUpdates, .macUpdate] {
            precondition(!prefs.isOn(feature))
        }
        var registrations = 0
        var removals = 0
        var granted = false
        let engine = CleaningModeEngine(now: { 0 }, register: { _ in
            registrations += 1
            return UUID()
        }, unregister: { _ in removals += 1 }, facts: { (true, granted) },
        schedule: { _, _, _ in {} })
        let cleaning = CleaningModeModule(engine: engine, granted: { granted })
        cleaning.begin()
        cleaning.start()
        cleaning.begin()
        precondition(registrations == 0 && cleaning.needsGrant)
        granted = true
        cleaning.begin()
        cleaning.stop()
        cleaning.begin()
        precondition(registrations == 1 && removals == 1 && !engine.isActive)

        var checks = 0
        var pending: CheckedContinuation<[AppUpdate], Never>?
        let updates = AppUpdatesModule {
            checks += 1
            return await withCheckedContinuation { pending = $0 }
        }
        let row = AppUpdate(app: .init(id: "fixture", version: "1", build: "1"),
                            source: nil, latest: "2", link: nil, isNewer: true)
        updates.check()
        precondition(checks == 0)
        updates.start()
        updates.check()
        while pending == nil { await Task.yield() }
        pending?.resume(returning: [row])
        pending = nil
        while updates.checking { await Task.yield() }
        precondition(updates.results == [row])
        updates.check()
        while pending == nil { await Task.yield() }
        updates.stop()
        pending?.resume(returning: [row])
        for _ in 0..<20 { await Task.yield() }
        precondition(updates.results.isEmpty && checks == 2)
        updates.check()
        precondition(checks == 2)

        let runner = ToolsFakeRunner()
        let service = MacUpdateService(runner: runner, appRoot: "/fixture",
                                      exists: { _ in true }, resolve: { $0 }, locked: { false },
                                      locate: { "/fixture/" + $0 })
        let mac = MacUpdateModule(service: service)
        var confirmations = 0
        mac.run { confirmations += 1; return true }
        precondition(confirmations == 0 && runner.calls == 0)
        mac.start()
        mac.run { confirmations += 1; return false }
        while mac.running { await Task.yield() }
        precondition(confirmations == 1 && runner.calls == 0)
        var confirmation: CheckedContinuation<Bool, Never>?
        mac.run { await withCheckedContinuation { confirmation = $0 } }
        while confirmation == nil { await Task.yield() }
        mac.stop()
        confirmation?.resume(returning: true)
        for _ in 0..<20 { await Task.yield() }
        precondition(runner.calls == 0 && mac.progress.isEmpty)
        mac.start()
        mac.run { true }
        while mac.running { await Task.yield() }
        precondition(runner.calls == 4 && mac.progress.count == 4)
        runner.blocks = true
        mac.run { true }
        while runner.calls == 4 { await Task.yield() }
        await mac.stopForTermination()
        precondition(runner.reaped)
        print("PASS defaults off; denied Start; stop unregisters; fake results; stale results dropped; confirmation")
    }
}
