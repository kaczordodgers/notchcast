import AppKit

extension ScreenshotModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "screenshot-display", name: String(localized: "Capture Screen", table: "Notchcast"), sfSymbol: "camera", feature: .screenshot,
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
                AppCore.shared.showMessage(Self.failureMessage(error), tone: .danger)
            }
        }
    }

    static func failureMessage(_ error: any Error) -> String {
        let failure = error as NSError
        if failure.domain == NSCocoaErrorDomain && (512..<1024).contains(failure.code) {
            return String(localized: "Could not save the screenshot.", table: "Notchcast")
        }
        return switch error as? ScreenshotRequest.Failure {
        case .permissionDenied: String(localized: "Screen Recording access is required.", table: "Notchcast")
        case .clipboardFailed: String(localized: "Could not copy to clipboard.", table: "Notchcast")
        case .disabled: String(localized: "Capture is disabled.", table: "Notchcast")
        case .invalidRect, .targetUnavailable: String(localized: "Capture area is unavailable.", table: "Notchcast")
        case .encodingFailed, nil: String(localized: "Could not capture the screen.", table: "Notchcast")
        }
    }
}
