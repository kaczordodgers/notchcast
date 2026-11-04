import Foundation

extension BlockedDialogModule {
    nonisolated static let checkCommand = NotchcastCommand(
        slug: "check-other-mac-dialogs", name: String(localized: "Check Other Mac Dialogs"),
        sfSymbol: "rectangle.on.rectangle", feature: .machBlockedDialogAlert,
        isEnabled: {
            [.machLink, .island, .islandStatusMessages, .machBlockedDialogAlert]
                .allSatisfy { NotchcastPreferences.shared.isOn($0) }
        }, run: {
            NotchcastCore.blockedDialogs.checkAndReport()
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
                NotchcastCore.remoteResult(String(localized: "Other Mac: \(owner) is waiting."))
                return
            }
            NotchcastCore.remoteResult(failed
                ? String(localized: "Could Not Check Other Mac Dialogs")
                : String(localized: "Other Mac Dialog Check Complete"))
        }
    }
}
