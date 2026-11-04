// notchcast-sources: Tinycast/Features/MachineBackup/Model/*.swift Tinycast/Features/MachineBackup/Service/MachineBackupCoordinator*.swift Tinycast/Features/MachineBackup/Service/MachineBackupTooling.swift
// notchcast-sources: Tinycast/Features/Notchcast/Core/Notchcast[FMP]*.swift
import Foundation
import Synchronization

struct NotchcastCommand: Sendable {
    let slug: String
    let name: String
    let sfSymbol: String
    let isEnabled: @MainActor @Sendable () -> Bool
    let run: @MainActor @Sendable () -> Void
}

private final class FakeBackupRunner: MachineBackupTooling {
    let requests = Mutex<[MachineBackupRequest]>([])
    let fails = Mutex(false)

    func run(_ request: MachineBackupRequest) async throws -> Data {
        requests.withLock { $0.append(request) }
        if fails.withLock({ $0 }) { throw MachineBackupFailure.toolFailed(1) }
        return Data()
    }
}

@MainActor
enum NotchcastCore {
    fileprivate static let runner = FakeBackupRunner()
    static let machineBackup = MachineBackupCoordinator(tooling: runner, preferences: .shared)
}

@main
struct MachineBackupCommandTest {
    @MainActor
    static func main() async throws {
        let feature = NotchcastFeature.backupRunNow
        let preferences = NotchcastPreferences.shared
        let previous = preferences.isOn(feature)
        defer { preferences.set(feature, previous) }
        preferences.set(feature, true)
        let coordinator = NotchcastCore.machineBackup
        coordinator.start()
        var messages: [String] = []
        coordinator.showMessage = { messages.append($0) }
        let command = MachineBackupCoordinator.launcherCommand
        precondition(command.slug == "mach-backup-run-now" && command.isEnabled())
        command.run()
        await coordinator.commandTask?.value
        precondition(messages.last == String(localized: "Machine backup is not configured."))
        precondition(NotchcastCore.runner.requests.withLock { $0.isEmpty })
        try coordinator.configure(MachineBackupConfiguration(
            jobLabel: "test.backup", userID: 501,
            resticExecutable: URL(fileURLWithPath: "/fixture/restic"),
            repository: "fixture", host: "fixture", passwordCommand: "/fixture/password",
            homeDirectory: URL(fileURLWithPath: "/Users/fixture")))
        command.run()
        await coordinator.commandTask?.value
        precondition(messages.last == String(localized: "Backup requested."))
        precondition(NotchcastCore.runner.requests.withLock {
            $0.count == 1 && $0[0].arguments == ["kickstart", "gui/501/test.backup"]
        })
        NotchcastCore.runner.fails.withLock { $0 = true }
        command.run()
        await coordinator.commandTask?.value
        precondition(messages.last == String(localized: "Could not request a backup."))
        preferences.set(feature, false)
        precondition(!command.isEnabled())
        command.run()
        await coordinator.commandTask?.value
        precondition(messages.last == String(localized: "Machine backup is disabled."))
        precondition(NotchcastCore.runner.requests.withLock { $0.count == 2 })
        coordinator.stop()
        print("PASS: backup command availability, unconfigured refusal, request and failure messages")
    }
}
