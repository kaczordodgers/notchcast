import Foundation

extension ClearNotificationsModule {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "clear-notifications", name: String(localized: "Clear Notifications", table: "Notchcast"),
        sfSymbol: "bell.slash", feature: .clearNotifications,
        isEnabled: { NotchcastPreferences.shared.isOn(.clearNotifications) },
        run: { ClearNotificationsModule.shared.clearFromLauncher() })

    func clearFromLauncher() {
        guard commandTask == nil else { return }
        let stamp = revision
        commandTask = Task { [weak self] in
            guard let self else { return }
            defer { if revision == stamp { commandTask = nil } }
            do {
                let count = try await run(accessibilityGranted: Permissions.isAccessibilityTrusted())
                try Task.checkCancellation()
                NotchcastHost.current.showMessage(String(localized: "Notifications cleared: \(count)", table: "Notchcast"), .neutral)
            } catch is CancellationError {
            } catch {
                guard isRunning, !Task.isCancelled else { return }
                let failure = error as? ClearNotificationsFailure ?? .invalidResult
                NotchcastHost.current.showMessage(failure.localizedDescription, .danger)
            }
        }
    }
}
