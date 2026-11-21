#if DEBUG
import AppKit

/// Exercises the dictation pill with injected audio levels and Return and Escape via the hold.
@MainActor
enum DictationIslandScenes {
    static let notch = CGSize(width: 185, height: 32)

    private final class Probe {
        var now: TimeInterval = 0
        var accepted = 0
        var cancelled = 0
    }

    static func run(scene: String, core: AppCore, controller: IslandController) async {
        let probe = Probe()
        let island = DictationIslandCoordinator(now: { probe.now })
        let away = scene.hasPrefix("dictation-away")
        let display = away ? controller.screen?.islandDisplayID : nil
        if away {
            IslandVerification.require(display != nil, "the non-resting pill has a display id")
            controller.showsRest = false
            controller.opened()
            IslandVerification.require(!controller.backdropWindow.isVisible, "the non-resting pill starts hidden")
        }
        island.attach(presenter: core.islandPresenter, covered: { false }, copies: { false },
                      typingDisplay: { display })
        defer { DictationPanelController.stand = nil }
        let capsule = DictationPanelController()
        capsule.onAccept = { probe.accepted += 1 }
        capsule.onCancel = { probe.cancelled += 1 }
        let heard = IslandVerification.announcements.count
        let hint = String(localized: "Return to Paste · Esc to Cancel", table: "Notchcast")
        func expect(_ text: String?, _ state: String) async {
            await IslandVerification.pause(0.15)
            print("DICTATION \(state) notice=\(controller.notice?.line ?? "nil") value=\(controller.accessibilityValue)"
                + " holds=\(island.holdsKeys) key=\(NSApp.keyWindow.map { "\(type(of: $0))" } ?? "nil")")
            IslandVerification.require(controller.notice?.text == text, "\(state): the pill shows \(text ?? "nothing")")
            if text != nil {
                if away {
                    IslandVerification.require(controller.backdropWindow.isVisible, "\(state): the placed pill is visible")
                }
                await controller.capture("\(scene)-\(state)")
            }
        }

        capsule.state.phase = .transcribing
        capsule.show()
        IslandVerification.require(capsule.state.phase == .listening, "the stand-in resets the capsule's phase")
        capsule.state.levels = (0..<DictationSpectrum.barCount).map { Float($0 % 5) / 4 }
        await expect(hint, "recording-start")
        IslandVerification.require(controller.notice?.meter?.count == 4, "recording draws four bars")
        let recording = String(localized: "Recording dictation", table: "Notchcast")
        IslandVerification.require(controller.accessibilityValue.contains(recording),
                                   "VoiceOver hears the sentence, not the time")
        probe.now = 7
        capsule.state.levels = capsule.state.levels.reversed()
        await expect(hint, "recording-0-07")
        IslandVerification.require(controller.notice?.progress?.readout == "0:07", "the time ticks from the clock")
        IslandVerification.require(island.holdsKeys, "the island holds the keys while recording")
        if away {
            let keyFrame = NSApp.keyWindow?.frame ?? .null
            IslandVerification.require(!keyFrame.isNull && controller.backdropWindow.frame.contains(keyFrame),
                                       "the key panel is anchored inside the placed pill's window")
        }
        await IslandInputScenes.key(36)
        IslandVerification.require(probe.accepted == 1 && probe.cancelled == 0, "a real Return reaches accept")

        capsule.state.phase = .transcribing
        await expect(String(localized: "Transcribing", table: "Notchcast"), "transcribing")
        island.cleaningUp()
        await expect(String(localized: "Cleaning Up", table: "Notchcast"), "cleaning-up")
        island.delivered(empty: false)
        IslandVerification.require(!island.holdsKeys, "the keys go back once the text is final")
        island.reset(completed: true)
        await expect(IslandNotice(dictation: .pasted).text, "pasted")
        IslandVerification.require(controller.notice?.quiet == true, "pasted is quiet beside a notch")
        await IslandInputScenes.key(53)
        IslandVerification.require(probe.cancelled == 0, "no hold is left behind after the result")
        IslandVerification.require(IslandVerification.announcements.count == heard + 2,
                                   "one announcement at the start and one for the result")

        if away {
            await IslandVerification.pause(IslandNotice.messageSeconds + 0.3)
            IslandVerification.require(controller.notice == nil && !controller.backdropWindow.isVisible,
                                       "the placed result expires and the pill hides")
            capsule.onCancel = { probe.cancelled += 1; island.reset(completed: false) }
            capsule.show()
            await expect(hint, "again")
            await IslandInputScenes.key(53)
            await expect(nil, "cancelled")
            await IslandVerification.pause(0.15)
            IslandVerification.require(probe.cancelled == 1 && !controller.backdropWindow.isVisible,
                                       "Escape reaches cancel and the placed pill hides")
            return
        }

        capsule.show()
        await expect(hint, "quick")
        capsule.state.phase = .transcribing
        island.delivered(empty: false)
        island.reset(completed: true)
        await expect(IslandNotice(dictation: .pasted).text, "quick-pasted")
        IslandVerification.require(IslandVerification.announcements.count == heard + 4,
                                   "a second session inside the last result's dwell is heard twice")

        capsule.show()
        await expect(hint, "again")
        let startLook = controller.canvas.look
        let flipped: IslandLook = startLook == .black ? .frosted : .black
        let display = controller.screen?.islandDisplayUUID
        core.island.looks.set(flipped, uuid: display)
        await IslandVerification.pause(0.15)
        IslandVerification.require(controller.canvas.look == flipped, "the look flips during recording")
        let document = NSPanel(contentRect: CGRect(x: 50, y: 50, width: 100, height: 100),
                               styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        document.makeKeyAndOrderFront(nil)
        IslandVerification.require(document.isKeyWindow, "the document takes key focus after the look changes")
        await IslandVerification.pause(0.15)
        await IslandInputScenes.key(53)
        IslandVerification.require(probe.cancelled == 1 || controller.notice?.text != hint,
                                   "Escape reaches cancel after a focus loss, or the hint is gone")
        document.orderOut(nil)
        core.island.looks.set(startLook, uuid: display)
        island.reset(completed: false)
        await expect(nil, "cancelled")

        for (sentence, outcome, state) in [
            (DictationIslandSession.noSpeech, DictationIslandSession.Outcome.noSpeech, "no-speech"),
            (DictationIslandSession.pasteFailed, .pasteFailed, "paste-failed"), ("The model stopped", .failed, "failed"),
        ] {
            capsule.show()
            capsule.state.phase = .transcribing
            await IslandVerification.pause(0.1)
            island.reset(completed: true)
            let swallowed = island.message(sentence)
            IslandVerification.require(swallowed == (outcome != .failed), "\(state): stock's report is taken")
            await expect(IslandNotice(dictation: outcome).text, state)
        }
        print("DICTATION announcements=\(IslandVerification.announcements.dropFirst(heard))")
    }
}
#endif
