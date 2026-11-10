import AppKit

extension CaptureEditorCoordinator {
    nonisolated static let launcherCommand = NotchcastCommand(
        slug: "capture-edit", name: String(localized: "Edit Capture", table: "Notchcast"),
        sfSymbol: "pencil.tip.crop.circle", feature: .captureEditor,
        isEnabled: { NotchcastPreferences.shared.isOn(.captureEditor) },
        run: {
            do {
                try CaptureEditorCoordinator.shared.openFromClipboardOrLast()
            } catch {
                NotchcastHost.current.showMessage(error.localizedDescription, .danger)
            }
        })
}
