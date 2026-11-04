import AppKit

@MainActor
final class MachRemoteModule: NotchcastModule {
    func start() { AppCore.shared.appIndex.refreshNotchcastCommands() }
    func stop() { AppCore.shared.appIndex.refreshNotchcastCommands() }

    func openTerminal() {
        guard NotchcastPreferences.shared.isOn(.machRemote) else { return }
        let ssh = MachSSH(address: NotchcastPreferences.shared.remoteMacAddress, runner: MachSSHProcessRunner.run)
        let script: String
        do { script = try ssh.terminalScript(directory: NotchcastPreferences.shared.remoteTerminalDirectory) } catch {
            NotchcastCore.remoteNotice(error.localizedDescription)
            return
        }
        let escaped = script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        var error: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil {
            AppCore.shared.showMessage(String(localized: "Unable to open Terminal"), tone: .danger)
        }
    }
}
