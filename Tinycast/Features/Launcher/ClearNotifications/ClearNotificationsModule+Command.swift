import Foundation

extension ClearNotificationsModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "clear-notifications", name: String(localized: "Clear Notifications", table: "Notchcast"),
        sfSymbol: "bell.slash", feature: .clearNotifications,
        isEnabled: { NotchcastPreferences.shared.isOn(.clearNotifications) },
        run: { NotchcastCore.clearNotifications.clearFromLauncher() })

    func clearFromLauncher() {
        commandTask?.cancel()
        commandTask = Task { [weak self] in
            guard let self else { return }
            do {
                let count = try await run(accessibilityGranted: Permissions.isAccessibilityTrusted())
                try Task.checkCancellation()
                AppCore.shared.showMessage(String(localized: "Notifications cleared: \(count)", table: "Notchcast"), tone: .neutral)
            } catch is CancellationError {
            } catch {
                guard isRunning, !Task.isCancelled else { return }
                let message = String(localized: "Could not clear notifications. Check Accessibility and Automation access.", table: "Notchcast")
                AppCore.shared.showMessage(message, tone: .danger)
            }
        }
    }
}
