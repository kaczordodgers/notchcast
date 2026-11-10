import AppKit

extension ScreenshotModule {
    nonisolated static let areaCommand = NotchcastCommand(
        slug: "screenshot-area", name: String(localized: "Capture Area", table: "Notchcast"),
        sfSymbol: "camera.viewfinder", feature: .screenshot,
        isEnabled: { NotchcastPreferences.shared.isOn(.screenshot) },
        run: { ScreenshotModule.shared.captureArea() })

    func captureArea() {
        guard enabled else { return }
        commandTask?.cancel()
        do {
            try area.start { [weak self] selection in
                guard let self, self.enabled, let selection else { return }
                self.commandTask = Task { [weak self] in
                    do {
                        let url = try await self?.capture(.rect(selection.rect))
                        if NotchcastPreferences.shared.isOn(.captureEditor), let self {
                            do {
                                try self.openInEditor(url, self.destination != .file)
                            } catch {
                                NotchcastHost.current.showMessage(error.localizedDescription, .danger)
                            }
                        }
                    } catch is CancellationError {
                    } catch {
                        NotchcastHost.current.showMessage(Self.failureMessage(error), .danger)
                    }
                }
            }
        } catch {
            NotchcastHost.current.showMessage(Self.failureMessage(error), .danger)
        }
    }

    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "screenshot-display", name: String(localized: "Capture Screen", table: "Notchcast"), sfSymbol: "camera", feature: .screenshot,
        isEnabled: { NotchcastPreferences.shared.isOn(.screenshot) },
        run: { ScreenshotModule.shared.captureDisplay() })

    func captureDisplay() {
        guard let displayID = NSScreen.underCursor?.displayID else { return }
        commandTask?.cancel()
        commandTask = Task { [weak self] in
            do {
                _ = try await self?.capture(.display(displayID))
            } catch is CancellationError {
            } catch {
                NotchcastHost.current.showMessage(Self.failureMessage(error), .danger)
            }
        }
    }
}
