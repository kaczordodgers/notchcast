import AppKit

@MainActor
final class MachRemoteModule: NotchcastModule {
    var automation: Task<Void, Never>?

    func start() { NotchcastHost.current.refreshNotchcastCommands() }
    func stop() {
        automation?.cancel()
        automation = nil
        NotchcastHost.current.refreshNotchcastCommands()
    }

    func openTerminal() {
        guard NotchcastPreferences.shared.isOn(.machRemote) else { return }
        let ssh = MachSSH(address: NotchcastPreferences.shared.remoteMacAddress, runner: MachSSHProcessRunner.run)
        let script: String
        do { script = try ssh.terminalScript(directory: NotchcastPreferences.shared.remoteTerminalDirectory) } catch {
            NotchcastHost.current.remoteResult(error.localizedDescription)
            return
        }
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        automation?.cancel()
        automation = Task {
            let result = try? await MachSSHProcessRunner.run("/usr/bin/osascript", ["-e", source])
            guard !Task.isCancelled, result?.status != 0 else { return }
            NotchcastHost.current.showMessage(String(localized: "Unable to open Terminal", table: "Notchcast"), .danger)
        }
    }
}
