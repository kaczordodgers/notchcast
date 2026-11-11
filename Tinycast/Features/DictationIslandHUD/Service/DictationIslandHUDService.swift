import AppKit
import Observation

@MainActor
final class DictationIslandHUDService {
    private weak var panel: NSPanel?
    private var state: DictationDisplayState?
    private var origin = NSPoint.zero
    private var progress: (notice: IslandActivityCenter.NoticeHandle, text: String)?
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
        if let progress { IslandActivityCenter.shared.dismiss(progress.notice) }
        progress = nil
    }

    private func update() {
        guard let panel, let state else { return }
        let current = generation
        let presentation = withObservationTracking {
            _ = IslandActivityCenter.shared.message
            return DictationIslandHUDPolicy.presentation(
                phase: state.phase == .listening ? .listening : .transcribing,
                enabled: NotchcastPreferences.shared.isOn(.dictationIslandHUD),
                islandAvailable: NotchcastPreferences.shared.showsStatusMessages
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
        if let progress, progress.text == text, IslandActivityCenter.shared.isShowing(progress.notice) { return }
        guard let notice = IslandHUDRouter.progress(text) else {
            dismiss()
            panel.setFrameOrigin(origin)
            return
        }
        progress = (notice, text)
        let rightEdge = NSScreen.screens.map(\.frame.maxX).max() ?? panel.frame.maxX
        // Keep the upstream key panel alive so Return and Escape retain their synchronous handlers.
        panel.setFrameOrigin(NSPoint(x: rightEdge + panel.frame.width, y: origin.y))
    }
}
