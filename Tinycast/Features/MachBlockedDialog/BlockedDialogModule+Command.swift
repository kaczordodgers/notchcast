import Foundation

extension BlockedDialogModule {
    nonisolated static let checkCommand = NotchcastCommand(
        slug: "check-other-mac-dialogs", name: String(localized: "Check Other Mac Dialogs", table: "Notchcast"),
        sfSymbol: "rectangle.on.rectangle", feature: .machBlockedDialogAlert,
        isEnabled: {
            [.machLink, .island, .islandStatusMessages, .machBlockedDialogAlert]
                .allSatisfy { NotchcastPreferences.shared.isOn($0) }
        }, run: {
            guard let module = BlockedDialogModule.shared else {
                return NotchcastHost.current.remoteResult(String(localized: "Could Not Check Other Mac Dialogs", table: "Notchcast"))
            }
            module.checkAndReport()
        })

    func checkAndReport() {
        guard isRunning else { return }
        let token = generation
        check()
        Task { [weak self] in
            guard let self else { return }
            await waitUntilIdle()
            guard !Task.isCancelled, isRunning, generation == token else { return }
            if !failed, let owner = detectedOwner {
                NotchcastHost.current.remoteResult(String(localized: "Other Mac: \(owner) is waiting.", table: "Notchcast"))
                return
            }
            NotchcastHost.current.remoteResult(failed
                ? String(localized: "Could Not Check Other Mac Dialogs", table: "Notchcast")
                : String(localized: "Other Mac Dialog Check Complete", table: "Notchcast"))
        }
    }
}
