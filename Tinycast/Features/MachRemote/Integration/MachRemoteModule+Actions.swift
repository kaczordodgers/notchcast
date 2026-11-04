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
        return paths
        """
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else {
            NotchcastCore.remoteNotice(String(localized: "Select files in Finder and configure the remote Mac.",
                                             table: "SendFiles"))
            return
        }
        let urls = (0..<result.numberOfItems).compactMap { index in
            result.atIndex(index + 1)?.stringValue.map { URL(fileURLWithPath: $0) }
        }
        NotchcastCore.sendFiles.send(urls)
    }
}
