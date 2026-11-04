// notchcast-sources: Tinycast/Features/MacUpdate/*/*.swift Tinycast/Features/MacUpdate/MacUpdateModule.swift
// notchcast-sources: Tinycast/Platform/ProcessExit.swift
import Foundation
@MainActor protocol NotchcastModule: AnyObject { func start(); func stop() }
@MainActor final class FakeRunner: MacUpdateProcessRunning {
    var calls = 0
    func run(_ command: MacUpdateCommand) async throws -> MacUpdateRunner.Result {
        calls += 1
        return .init(status: 0, output: "")
    }
}
@main struct ModuleTest {
    @MainActor static func main() async {
        let fake = FakeRunner()
        let service = MacUpdateService(runner: fake, home: "/fixture", appRoot: "/fixture",
            exists: { _ in false }, resolve: { $0 }, locked: { false })
        let module = MacUpdateModule(service: service)
        var pending: CheckedContinuation<Bool, Never>?
        module.run { preconditionFailure("Disabled confirmation") }
        precondition(!module.running)
        module.start()
        module.run { await withCheckedContinuation { pending = $0 } }
        while pending == nil { await Task.yield() }
        module.stop()
        pending?.resume(returning: true)
        for _ in 0..<20 { await Task.yield() }
        precondition(!module.running && module.progress.isEmpty && fake.calls == 0)
        module.start()
        module.run { true }
        for _ in 0..<100 { await Task.yield() }
        await module.stopForTermination()
        precondition(!module.running && fake.calls == 0)
        print("PASS start, stop, switch off during confirmation and termination")
    }
}
