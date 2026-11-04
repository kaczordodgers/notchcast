import Foundation
import Darwin

nonisolated struct SystemToolsProcessRunner: Sendable {
    enum Failure: Error { case invalidExecutable, timedOut, failed(Int32) }

    func run(_ executable: String, arguments: [String], timeout: TimeInterval = 5) throws -> String {
        try Task.checkCancellation()
        guard ["/bin/launchctl", "/usr/bin/defaults", "/bin/kill"].contains(executable) else {
            throw Failure.invalidExecutable
        }
        let outputURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.environment = [:]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exit = try process.runObservingExit()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled {
                Darwin.kill(process.processIdentifier, SIGKILL)
                exit.wait()
                throw CancellationError()
            }
            if Date() >= deadline {
                Darwin.kill(process.processIdentifier, SIGKILL)
                exit.wait()
                throw Failure.timedOut
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        exit.wait()
        guard process.terminationStatus == 0 else { throw Failure.failed(process.terminationStatus) }
        return try String(contentsOf: outputURL, encoding: .utf8)
    }

    @concurrent
    func startupItems(home: String, uid: UInt32) async throws -> [StartupItem] {
        var items: [StartupItem] = []
        let disabledText = try run("/bin/launchctl", arguments: ["print-disabled", "gui/\(uid)"])
        for (folder, kind) in [(home + "/Library/LaunchAgents", StartupItem.Kind.userAgent),
                               ("/Library/LaunchAgents", .systemAgent),
                               ("/System/Library/LaunchAgents", .systemAgent)] {
            guard FileManager.default.fileExists(atPath: folder) else { continue }
            for item in try StartupItemService().read(folder: URL(filePath: folder), kind: kind) {
                let loaded: Bool
                do {
                    _ = try run("/bin/launchctl", arguments: ["print", "gui/\(uid)/\(item.label)"])
                    loaded = true
                } catch Failure.failed(113) {
                    loaded = false
                }
                let disabled = disabledText.contains("\"\(item.label)\" => true")
                items.append(StartupItem(label: item.label, kind: item.kind, path: item.path,
                                         program: item.program, disabled: disabled, loaded: loaded))
            }
        }
        return items
    }

    @concurrent
    func setStartupItem(_ item: StartupItem, enabled: Bool, home: String, uid: UInt32) async throws {
        let current = try await startupItems(home: home, uid: uid).first { $0.path == item.path }
        guard current == item else { throw StartupItem.Failure.unknownState }
        try StartupItemService().apply(item, enabled: enabled, uid: uid, home: home) {
            _ = try run("/bin/launchctl", arguments: $0)
        }
    }

    @concurrent
    func stopProcesses(_ targets: [KillProcessEntry], signal: KillProcessService.Signal,
                       uid: UInt32, ownPID: Int32) async throws {
        let service = KillProcessService()
        try service.apply(targets: targets, signal: signal, uid: uid, ownPID: ownPID,
                          lookup: service.read(pid:)) { pid, signal in
            _ = try run("/bin/kill", arguments: ["-\(signal.rawValue)", String(pid)])
        }
    }

    @concurrent
    func apply(_ plan: MacSetupPlan) async -> TweakPlanRunner.Receipt {
        TweakPlanRunner().apply(plan) { preference, value in
            let command = TweakCommand.preference(preference, value: value)
            _ = try run(command.executable, arguments: command.arguments)
        }
    }
}
