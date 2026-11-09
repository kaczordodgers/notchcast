import AppKit

extension ScreenshotModule {
    nonisolated static let areaCommand = NotchcastCommand(
        slug: "screenshot-area", name: String(localized: "Capture Area", table: "Notchcast"),
        sfSymbol: "camera.viewfinder", feature: .screenshot,
        isEnabled: { NotchcastPreferences.shared.isOn(.screenshot) },
        run: { NotchcastCore.screenshot.captureArea() })

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
                                try NotchcastCore.captureEditor.openCapture(url: url, clipboard: self.destination != .file)
                            } catch {
                                AppCore.shared.showMessage(error.localizedDescription, tone: .danger)
                            }
                        }
                    } catch is CancellationError {
                    } catch {
                        AppCore.shared.showMessage(Self.failureMessage(error), tone: .danger)
                    }
                }
            }
        } catch {
            AppCore.shared.showMessage(Self.failureMessage(error), tone: .danger)
        }
    }

    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "screenshot-display", name: String(localized: "Capture Screen", table: "Notchcast"), sfSymbol: "camera", feature: .screenshot,
        isEnabled: { NotchcastPreferences.shared.isOn(.screenshot) },
        run: { NotchcastCore.screenshot.captureDisplay() })

    func captureDisplay() {
        guard let displayID = NSScreen.underCursor?.displayID else { return }
        commandTask?.cancel()
        commandTask = Task { [weak self] in
            do {
                _ = try await self?.capture(.display(displayID))
            } catch is CancellationError {
            } catch {
                AppCore.shared.showMessage(Self.failureMessage(error), tone: .danger)
            }
        }
    }
}
