import AppKit

extension MachRemoteModule {
    func update() { NotchcastCore.updateRemote.update() }

    func sendFinderSelection() {
        guard NotchcastPreferences.shared.isOn(.machRemote), NotchcastPreferences.shared.isOn(.sendFiles) else { return }
        let source = """
        tell application "Finder" to set chosenItems to selection as alias list
        set paths to {}
        repeat with chosenItem in chosenItems
            set end of paths to POSIX path of chosenItem
        end repeat
        set AppleScript's text item delimiters to linefeed
        return paths as text
        """
        automation?.cancel()
        automation = Task {
            let result = try? await MachSSHProcessRunner.run("/usr/bin/osascript", ["-e", source])
            guard !Task.isCancelled, NotchcastPreferences.shared.isOn(.machRemote),
                  NotchcastPreferences.shared.isOn(.sendFiles) else { return }
            guard let result, result.status == 0 else {
                NotchcastCore.remoteResult(String(localized: "Select files in Finder and configure the remote Mac.",
                                                  table: "SendFiles"))
                return
            }
            NotchcastCore.sendFiles.send(result.output.split(separator: "\n").map { URL(fileURLWithPath: String($0)) })
        }
    }
}
