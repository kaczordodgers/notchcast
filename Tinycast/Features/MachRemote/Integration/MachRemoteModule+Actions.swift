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
        set AppleScript's text item delimiters to character id 0
        if (count of paths) is 0 then return ""
        return (paths as text) & (character id 0)
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
            let paths = result.output.split(separator: "\0", omittingEmptySubsequences: false)
            guard paths.last == "\n" || paths.last == "",
                  paths.dropLast().allSatisfy({ $0.hasPrefix("/") }) else { return }
            NotchcastCore.sendFiles.send(paths.dropLast().map { URL(fileURLWithPath: String($0)) })
        }
    }
}
