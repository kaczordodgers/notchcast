import AppKit

extension ScreenshotModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "screenshot-display", name: String(localized: "Capture Screen"), sfSymbol: "camera",
        isEnabled: { NotchcastPreferences.shared.isOn(.screenshot) },
        run: { NotchcastCore.screenshot.captureDisplay() })

    func captureDisplay() {
        guard let number = NSScreen.underCursor?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? NSNumber else { return }
        commandTask?.cancel()
        commandTask = Task { [weak self] in
            do {
                _ = try await self?.capture(.display(number.uint32Value))
            } catch is CancellationError {
            } catch {
                AppCore.shared.showMessage(String(localized: "Capture Screen"), tone: .danger)
            }
        }
    }
}
