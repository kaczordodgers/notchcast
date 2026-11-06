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
                            try NotchcastCore.captureEditor.openCapture(url: url, clipboard: self.destination != .file)
                        }
                    } catch is CancellationError {
                    } catch {
                        AppCore.shared.showMessage(Self.failureMessage(error), tone: .danger)
                    }
                }
            }
        } catch {
            AppCore.shared.showMessage(
                String(localized: "Screen Recording access is required.", table: "Notchcast"), tone: .danger)
        }
    }

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
