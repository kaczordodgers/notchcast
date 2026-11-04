import AppKit

extension NotchcastToolsCommands {
    convenience init(core: AppCore) {
        self.init(preferences: .shared, selection: Self.finderSelection, post: Self.post,
                  refresh: { [weak core] in core?.appIndex.refreshNotchcastCommands() }
        ) { [weak core] action, files, valid in
            guard let core, valid() else { return }
            switch action {
            case .convertFiles:
                guard NotchcastPreferences.shared.isOn(.downloads),
                      let downloads = NotchcastDownloadLauncherCommands.downloads else {
                    Self.post(String(localized: "Enable Downloads to convert files.")); return
                }
                await downloads.state.settle()
                guard valid(), NotchcastPreferences.shared.isOn(.downloads) else { return }
                guard let queue = downloads.state.queue else {
                    Self.post(String(localized: "Downloads is not ready.")); return
                }
                let formats = ["pdf", "png", "jpg", "txt", "zip", "mp3", "mp4"]
                guard let index = await Self.choose(core, title: action.name, values: formats), valid(),
                      NotchcastPreferences.shared.isOn(.downloads), downloads.state.queue === queue else { return }
                NotchcastCore.convertFiles.attach(to: queue, post: Self.post)
                try NotchcastCore.convertFiles.convert(files, target: formats[index])
            case .runHostCommand, .listCommands:
                let entries = await HostCommandProfile.load(
                    file: AppPaths.applicationSupport().appending(path: "Notchcast/host-commands.json"),
                    host: ProcessInfo.processInfo.hostName)
                guard valid() else { return }
                guard !entries.isEmpty else {
                    Self.post(String(localized: "No host commands configured.")); return
                }
                if action == .listCommands {
                    await core.showNotice(title: action.name, message: entries.map(\.title).joined(separator: "\n"),
                                      symbol: "terminal", tone: .neutral)
                    return
                }
                guard let index = await Self.choose(core, title: action.name, values: entries.map(\.title)),
                      valid() else { return }
                let result = try await CatalogShellCommandRunner(processRunner: CommandProcessRunner.run).run(entries[index])
                guard valid() else { return }
                Self.post(result.succeeded ? String(localized: "Host command completed.")
                          : String(localized: "Host command failed."))
            default:
                let tool: MediaToolsRunner.Tool
                switch action {
                case .compressVideo: tool = .video()
                case .makeGIF: tool = .gif
                case .compressImage: tool = .image()
                case .resizeImage:
                    let dimensions = [640, 1024, 1600]
                    guard let index = await Self.choose(core, title: action.name,
                                                       values: dimensions.map(String.init)), valid() else { return }
                    tool = .image(maxDimension: dimensions[index])
                default: tool = .text
                }
                try await NotchcastCore.mediaTools.process(files, tool: tool, isCurrent: valid, post: Self.post)
            }
        }
        NotchcastToolsLauncherCommands.controller = self
    }

    private static func choose(_ core: AppCore, title: String, values: [String]) async -> Int? {
        let options = values.map { DialogAction(title: $0, role: .standard) }
            + [DialogAction(title: String(localized: "Cancel"), role: .cancel)]
        let index = await core.choose(title: title, message: nil, symbol: "wrench.and.screwdriver",
                                      options: options, defaultIndex: 0)
        return values.indices.contains(index) ? index : nil
    }

    private static func post(_ text: String) {
        IslandActivityCenter.shared.showMessage(text, tone: .neutral, dwell: 4)
    }

    private static func finderSelection() throws -> [URL] {
        let script = """
            tell application "Finder"
                set chosen to selection as alias list
            end tell
            set paths to {}
            repeat with itemAlias in chosen
                set end of paths to POSIX path of itemAlias
            end repeat
            return paths
            """
        guard let apple = NSAppleScript(source: script) else { return [] }
        var error: NSDictionary?
        let result = apple.executeAndReturnError(&error)
        guard error == nil else { throw CocoaError(.fileReadNoPermission) }
        return (0..<result.numberOfItems).compactMap {
            result.atIndex($0 + 1)?.stringValue.map { URL(fileURLWithPath: $0) }
        }
    }
}
