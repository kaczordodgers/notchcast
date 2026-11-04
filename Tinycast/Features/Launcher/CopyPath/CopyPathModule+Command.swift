import AppKit

extension CopyPathModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "copy-path", name: String(localized: "Copy Path"), sfSymbol: "doc.on.clipboard", feature: .copyPath,
        isEnabled: { NotchcastPreferences.shared.isOn(.copyPath) },
        run: {
            let app = NSWorkspace.shared.menuBarOwningApplication
            let target = app.map { CopyPathTarget(processID: $0.processIdentifier, bundleID: $0.bundleIdentifier) }
            NotchcastCore.copyPath.copyFromLauncher(target: target, home: NSHomeDirectory())
        })

    func copyFromLauncher(target: CopyPathTarget?, home: String,
                          copy: @escaping (String) -> Bool = {
                              NSPasteboard.general.clearContents()
                              return NSPasteboard.general.setString($0, forType: .string)
                          },
                          report: @escaping (String) -> Void = {
                              AppCore.shared.showMessage($0, tone: .neutral)
                          }) {
        guard isRunning, let service else { return }
        commandTask?.cancel()
        commandTask = Task { [weak self] in
            do {
                let result = try await service.resolve(target: target, home: home)
                guard !Task.isCancelled, self?.isRunning == true else { return }
                switch result {
                case .path(let text), .link(let text):
                    report(copy(text) ? String(localized: "Copied path") : String(localized: "Could not copy to clipboard."))
                case .nothing:
                    report(String(localized: "Unavailable"))
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, self?.isRunning == true else { return }
                report(String(localized: "Could not copy to clipboard."))
            }
        }
    }
}
