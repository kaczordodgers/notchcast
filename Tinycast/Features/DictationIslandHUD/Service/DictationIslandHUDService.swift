import AppKit
import Observation

@MainActor
final class DictationIslandHUDService {
    private weak var panel: NSPanel?
    private var state: DictationDisplayState?
    private var origin = NSPoint.zero
    private var messageID: UUID?
    private var messageText: String?
    private var generation = 0

    func show(panel: NSPanel, state: DictationDisplayState) {
        close()
        self.panel = panel
        self.state = state
        origin = panel.frame.origin
        update()
    }

    func close() {
        generation += 1
        dismiss()
        panel?.setFrameOrigin(origin)
        panel = nil
        state = nil
    }

    private func dismiss() {
        if let messageID, let message = IslandActivityCenter.shared.message,
            message.id == messageID, message.text == messageText, message.isProgress {
            IslandHUDRouter.dismiss()
        }
        messageID = nil
        messageText = nil
    }

    private func update() {
        guard let panel, let state else { return }
        let current = generation
        let presentation = withObservationTracking {
            _ = IslandActivityCenter.shared.message
            return DictationIslandHUDPolicy.presentation(
                phase: state.phase == .listening ? .listening : .transcribing,
                enabled: NotchcastPreferences.shared.isOn(.dictationIslandHUD),
                islandAvailable: NotchcastPreferences.shared.isOn(.island)
                    && NotchcastPreferences.shared.isOn(.islandStatusMessages)
                    && IslandActivityCenter.shared.hasPresenter)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                self.update()
            }
        }
        guard presentation != .capsule else {
            dismiss()
            panel.setFrameOrigin(origin)
            return
        }
        let text = presentation == .listening
            ? String(localized: "Dictation listening") : String(localized: "Transcribing dictation")
        let message = IslandActivityCenter.shared.message
        guard DictationIslandHUDPolicy.shouldShowProgress(
            presentation: presentation,
            ownsMessage: message != nil && message?.id == messageID
                && message?.text == text && message?.isProgress == true) else { return }
        guard IslandHUDRouter.showProgress(text, onCancel: nil) else {
            dismiss()
            panel.setFrameOrigin(origin)
            return
        }
        messageID = IslandActivityCenter.shared.message?.id
        messageText = text
        let rightEdge = NSScreen.screens.map(\.frame.maxX).max() ?? panel.frame.maxX
        // Keep the upstream key panel alive so Return and Escape retain their synchronous handlers.
        panel.setFrameOrigin(NSPoint(x: rightEdge + panel.frame.width, y: origin.y))
    }
}
